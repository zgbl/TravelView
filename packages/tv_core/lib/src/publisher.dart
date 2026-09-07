import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 把导出好的 Story 目录发布到服务器。协议见 docs/publish-api.md。
///
/// 两步:
///   1. POST /api/publish  —— 服务器校验令牌、扣额度、建 story、
///      返回一批**预签名上传地址**
///   2. 逐个 PUT，图片**直传对象存储**，不经过我们的服务器
///
/// **原图永远不上传。** 这里只认导出目录里的 `photos/` 和 `thumbs/`，
/// 而且发送前再自己查一遍后缀 —— 服务器也查，但错误要在本地就拦住，
/// 不能等服务器返回 400 才发现 App 有 bug。
class PublishConfig {
  final String siteUrl; // https://travelview.app
  final String token;   // tv_xxxx

  const PublishConfig({required this.siteUrl, required this.token});

  bool get isConfigured =>
      siteUrl.trim().isNotEmpty && token.trim().isNotEmpty;

  String get _base => siteUrl.trim().replaceAll(RegExp(r'/+$'), '');
  Uri get publishUri => Uri.parse('$_base/api/publish');
}

class PublishException implements Exception {
  final String message;
  final int? statusCode;

  /// Story 已经在服务器上建好了，只是图没传完。
  /// **调用方必须把它存下来** —— 重试时带上它就是接着传那一篇，
  /// 而不是又建一篇、又扣一次额度。
  final String? storyId;

  /// 额度不够。桌面端据此引导用户去网页付款，而不是弹一个干巴巴的错误。
  bool get needsPayment => statusCode == 402;

  const PublishException(this.message, {this.statusCode, this.storyId});

  @override
  String toString() =>
      statusCode == null ? message : 'HTTP $statusCode: $message';
}

class PublishResult {
  final String slug;
  final String publicUrl;
  final int fileCount;
  final int totalBytes;

  /// 服务器给这篇 Story 的 id。**存下来** ——
  /// 下次发布同一趟行程时带上它，就是原地更新而不是新建一篇。
  final String storyId;

  /// true = 更新了已有的那一篇（链接没变）
  final bool updated;

  /// 这次实际扣了多少篇额度: 0 / 0.5 / 1
  final double charged;

  /// 这一篇累计更新过几次
  final int updateCount;

  const PublishResult({
    required this.slug,
    required this.publicUrl,
    required this.fileCount,
    required this.totalBytes,
    this.storyId = '',
    this.updated = false,
    this.charged = 0,
    this.updateCount = 0,
  });
}

/// 服务器上的一篇 Story（用来让用户挑要更新哪一篇）
class RemoteStory {
  final String id;
  final String slug;
  final String title;
  final String? start;
  final String? end;
  final int photos;
  final int stops;
  final bool published;
  final String url;

  /// 已经更新过几次。前 5 次免费，之后每次 0.5 篇额度
  final int updates;

  const RemoteStory({
    required this.id,
    required this.slug,
    required this.title,
    required this.photos,
    required this.stops,
    required this.published,
    required this.url,
    this.updates = 0,
    this.start,
    this.end,
  });

  factory RemoteStory.fromJson(Map<String, dynamic> j) => RemoteStory(
        id: j['id'] as String,
        slug: j['slug'] as String? ?? '',
        title: j['title'] as String? ?? '未命名',
        start: j['start'] as String?,
        end: j['end'] as String?,
        photos: (j['photos'] as num?)?.toInt() ?? 0,
        stops: (j['stops'] as num?)?.toInt() ?? 0,
        published: j['published'] == true,
        url: j['url'] as String? ?? '',
        updates: (j['updates'] as num?)?.toInt() ?? 0,
      );
}

/// 允许上传的后缀。**白名单，不是黑名单** ——
/// 新增一种原图格式时，不该因为忘了往黑名单里加就泄漏出去。
///
/// 为什么 jpg 也在里面: 导出用的是系统的图像编码器，
/// **某些图它编不出 WebP，会退回 JPEG**（exportWeb 的返回值里写了实际格式）。
/// 那张 JPEG 一样是 1600px、剥干净元数据的派生图 ——
/// 这条闸门要挡的是"原图被传上去"，不是某一种格式。
/// 原图格式（HEIC / DNG / CR2 / NEF / ARW）依然进不来。
const _allowedExt = {'.webp', '.jpg', '.jpeg'};

String _contentTypeOf(String ext) =>
    ext == '.webp' ? 'image/webp' : 'image/jpeg';

class Publisher {
  final PublishConfig config;
  final Duration timeout;

  /// 并发上传数。太高会被对象存储限流，4 在家用带宽下已经跑满。
  final int concurrency;

  const Publisher(
    this.config, {
    this.timeout = const Duration(seconds: 120),
    this.concurrency = 4,
  });

  /// 列出这个账号已经发布的故事。
  /// 用户据此挑"要更新哪一篇" —— 草稿里那条记录断了也还有路可走。
  Future<List<RemoteStory>> listStories() async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final base = config.siteUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final req = await client
          .getUrl(Uri.parse('$base/api/stories'))
          .timeout(timeout);
      req.headers.set('Authorization', 'Bearer ${config.token.trim()}');
      final res = await req.close().timeout(timeout);
      final body = await utf8.decoder.bind(res).join();
      if (res.statusCode >= 400) {
        throw PublishException(_errorOf(body, res.statusCode),
            statusCode: res.statusCode);
      }
      final list = (jsonDecode(body) as Map<String, dynamic>)['stories'] as List;
      return list
          .cast<Map<String, dynamic>>()
          .map(RemoteStory.fromJson)
          .toList();
    } on SocketException catch (e) {
      throw PublishException('连不上服务器: ${e.message}');
    } on TimeoutException {
      throw const PublishException('服务器没有响应（超时）');
    } finally {
      client.close(force: true);
    }
  }

  /// [exportDir] 就是 StoryExporter 产出的那个目录。
  /// [onCreated] 在 Story 建好、开始传图之前回调一次。
  /// 传图可能断，**这一步的 storyId 必须立刻落到调用方手里**，
  /// 否则重试只能重新建一篇。
  ///
  /// [storyId] 传了就是**原地更新那一篇**: 公开链接不变、不再扣额度。
  /// 服务器找不到这个 id（用户删了那篇、或换了账号）时会当作新建，
  /// 不会报错把人卡住 —— 照片都已经导出好了。
  Future<PublishResult> publish(
    Directory exportDir, {
    String visibility = 'public',
    String? storyId,
    void Function(String storyId)? onCreated,
    void Function(int done, int total, String label)? onProgress,
  }) async {
    if (!config.isConfigured) {
      throw const PublishException('还没有连接账号，先在设置里点「连接账号」');
    }

    final manifestFile = File(p.join(exportDir.path, 'story.json'));
    if (!await manifestFile.exists()) {
      throw const PublishException('导出目录里没有 story.json，先重新导出一次');
    }
    final manifest = jsonDecode(await manifestFile.readAsString());

    final files = await _collect(exportDir);
    if (files.isEmpty) {
      throw const PublishException('导出目录里没有可上传的图片');
    }

    onProgress?.call(0, files.length + 1,
        storyId == null ? '正在创建 Story' : '正在更新 Story');
    final created = await _createStory(manifest, files, visibility, storyId);

    final newId = created['storyId'] as String? ?? '';
    if (newId.isNotEmpty) onCreated?.call(newId);

    final uploads = (created['uploads'] as List)
        .cast<Map<String, dynamic>>()
        .map((e) => (
              path: e['path'] as String,
              url: e['url'] as String,
            ))
        .toList();
    final byPath = {for (final f in files) f.path: f};

    var done = 1;
    var bytes = 0;
    var skipped = 0;
    final total = files.length + 1;

    // 简单的固定并发池：完成一个补一个，不做整批等待
    final queue = List.of(uploads);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final u = queue.removeAt(0);
        final f = byPath[u.path];
        if (f == null) continue;
        final uri = Uri.parse(u.url);
        final len = await f.file.length();

        // 断点续传第一步: 这张已经在服务器上、而且大小一致，就跳过。
        // 一次发布上百张图，断一次重来全传是不可接受的
        if (await _alreadyThere(uri, len)) {
          skipped++;
          done++;
          onProgress?.call(done, total, '${u.path}（已传过）');
          continue;
        }

        final data = await f.file.readAsBytes();
        // 断点续传第二步: 单张自己重试几次。
        // 家用上行断一下是常态，不该让整篇发布跟着失败
        await _putWithRetry(uri, data, f.contentType, u.path);
        bytes += data.length;
        done++;
        onProgress?.call(done, total, u.path);
      }
    }

    try {
      await Future.wait([
        for (var i = 0; i < concurrency && i < uploads.length; i++) worker(),
      ]);
    } on PublishException catch (e) {
      // 把 storyId 带出去，调用方据此续传
      throw PublishException(e.message,
          statusCode: e.statusCode,
          storyId: newId.isEmpty ? storyId : newId);
    }

    // 第三步: 告诉服务器"传完了"。**额度在这一步才扣** ——
    // 图没传完就扣钱，等于用户付了钱什么都没拿到。
    onProgress?.call(total, total, '正在完成发布');
    // 注意别叫 done —— 上面那个 done 是上传进度的计数器
    final finish = await _complete(newId.isEmpty ? (storyId ?? '') : newId);

    return PublishResult(
      slug: created['slug'] as String,
      publicUrl: created['publicUrl'] as String,
      fileCount: files.length,
      totalBytes: bytes,
      storyId: created['storyId'] as String? ?? '',
      updated: created['updated'] == true,
      charged: (finish['charged'] as num?)?.toDouble() ?? 0,
      updateCount: (finish['updateCount'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<({String path, File file, String contentType})>> _collect(
      Directory dir) async {
    final out = <({String path, File file, String contentType})>[];
    for (final sub in const ['photos', 'thumbs']) {
      final d = Directory(p.join(dir.path, sub));
      if (!await d.exists()) continue;
      await for (final e in d.list()) {
        if (e is! File) continue;
        final ext = p.extension(e.path).toLowerCase();
        if (!_allowedExt.contains(ext)) {
          throw PublishException(
              '导出目录里有不该出现的文件 ${p.basename(e.path)}，'
              '为安全起见拒绝上传');
        }
        out.add((
          path: '$sub/${p.basename(e.path)}',
          file: e,
          contentType: _contentTypeOf(ext),
        ));
      }
    }
    // 分享预览图放在导出目录根下，不在 photos/ 里 —— 它不是一张作品照片，
    // 是社交平台专用的那一张卡片图
    final og = File(p.join(dir.path, 'og.jpg'));
    if (await og.exists()) {
      out.add((path: 'og.jpg', file: og, contentType: 'image/jpeg'));
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  Future<Map<String, dynamic>> _createStory(
      Object? manifest,
      List<({String path, File file, String contentType})> files,
      String visibility,
      String? storyId) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.postUrl(config.publishUri).timeout(timeout);
      req.headers.set('User-Agent', 'TravelView/0.1');
      req.headers.set('Authorization', 'Bearer ${config.token.trim()}');
      req.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      req.write(jsonEncode({
        'manifest': manifest,
        'visibility': visibility,
        if (storyId != null && storyId.isNotEmpty) 'storyId': storyId,
        'files': [
          for (final f in files)
            {
              'path': f.path,
              'contentType': f.contentType,
              'bytes': await f.file.length(),
            },
        ],
      }));
      final res = await req.close().timeout(timeout);
      final body = await utf8.decoder.bind(res).join();
      if (res.statusCode >= 400) {
        throw PublishException(_errorOf(body, res.statusCode),
            statusCode: res.statusCode);
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } on SocketException catch (e) {
      throw PublishException('连不上服务器: ${e.message}');
    } on TimeoutException {
      throw const PublishException('服务器没有响应（超时）');
    } finally {
      client.close(force: true);
    }
  }

  /// 收尾: 服务器点一遍文件，确认没缺，然后正式上线并扣额度。
  Future<Map<String, dynamic>> _complete(String id) async {
    if (id.isEmpty) return const {};
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client
          .postUrl(Uri.parse('$_completeUri'))
          .timeout(timeout);
      req.headers.set('Authorization', 'Bearer ${config.token.trim()}');
      req.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      req.write(jsonEncode({'storyId': id}));
      final res = await req.close().timeout(timeout);
      final body = await utf8.decoder.bind(res).join();
      if (res.statusCode >= 400) {
        throw PublishException(_errorOf(body, res.statusCode),
            statusCode: res.statusCode, storyId: id);
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } on SocketException catch (e) {
      throw PublishException('收尾时断开: ${e.message}', storyId: id);
    } on TimeoutException {
      throw PublishException('收尾超时', storyId: id);
    } finally {
      client.close(force: true);
    }
  }

  String get _completeUri =>
      '${config.siteUrl.trim().replaceAll(RegExp(r"/+\$"), "")}'
      '/api/publish/complete';

  /// 传过了吗。问不出来（服务器不支持 HEAD、网络抖）就当没传过 ——
  /// 重传一张的代价远小于漏传一张
  Future<bool> _alreadyThere(Uri url, int bytes) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.openUrl('HEAD', url)
          .timeout(const Duration(seconds: 15));
      final res = await req.close().timeout(const Duration(seconds: 15));
      await res.drain<void>();
      if (res.statusCode != 200) return false;
      final len = res.headers.contentLength;
      return len <= 0 || len == bytes;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// 单张重试。只重试**网络层**的失败;
  /// 403/413/415 这种是内容或票据不对，重试多少次都一样，直接抛。
  Future<void> _putWithRetry(
      Uri url, List<int> data, String contentType, String label) async {
    const delays = [
      Duration(seconds: 1),
      Duration(seconds: 3),
      Duration(seconds: 8),
    ];
    for (var attempt = 0; ; attempt++) {
      try {
        await _put(url, data, contentType);
        return;
      } on PublishException catch (e) {
        final code = e.statusCode;
        final retriable = code == null || code >= 500 || code == 408 ||
            code == 429;
        if (!retriable || attempt >= delays.length) rethrow;
        await Future<void>.delayed(delays[attempt]);
      }
    }
  }

  Future<void> _put(Uri url, List<int> data, String contentType) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.putUrl(url).timeout(timeout);
      // 预签名地址把 Content-Type 算进了签名，必须和申请时**一模一样**
      req.headers.set(HttpHeaders.contentTypeHeader, contentType);
      req.contentLength = data.length;
      req.add(data);
      final res = await req.close().timeout(timeout);
      final body = await utf8.decoder.bind(res).join();
      if (res.statusCode >= 400) {
        throw PublishException('上传失败: ${_errorOf(body, res.statusCode)}',
            statusCode: res.statusCode);
      }
    } on SocketException catch (e) {
      throw PublishException('上传中断: ${e.message}');
    } on TimeoutException {
      throw const PublishException('上传超时');
    } finally {
      client.close(force: true);
    }
  }

  static String _errorOf(String body, int code) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        if (j['error'] == 'NEED_PAYMENT') {
          return j['message'] as String? ?? '还没有可用的发布额度';
        }
        final m = j['message'] ?? j['error'];
        if (m is String && m.isNotEmpty) return m;
      }
    } catch (_) {}
    return body.trim().isEmpty ? 'HTTP $code' : body.trim();
  }
}
