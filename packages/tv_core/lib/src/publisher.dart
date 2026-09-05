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

  /// 额度不够。桌面端据此引导用户去网页付款，而不是弹一个干巴巴的错误。
  bool get needsPayment => statusCode == 402;

  const PublishException(this.message, {this.statusCode});

  @override
  String toString() =>
      statusCode == null ? message : 'HTTP $statusCode: $message';
}

class PublishResult {
  final String slug;
  final String publicUrl;
  final int fileCount;
  final int totalBytes;

  const PublishResult({
    required this.slug,
    required this.publicUrl,
    required this.fileCount,
    required this.totalBytes,
  });
}

/// 允许上传的后缀。**白名单，不是黑名单** ——
/// 新增一种原图格式时，不该因为忘了往黑名单里加就泄漏出去。
const _allowedExt = {'.webp'};

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

  /// [exportDir] 就是 StoryExporter 产出的那个目录。
  Future<PublishResult> publish(
    Directory exportDir, {
    String visibility = 'public',
    void Function(int done, int total, String label)? onProgress,
  }) async {
    if (!config.isConfigured) {
      throw const PublishException('还没有填发布令牌，先去网站 /account 生成');
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

    onProgress?.call(0, files.length + 1, '正在创建 Story');
    final created = await _createStory(manifest, files, visibility);

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
    final total = files.length + 1;

    // 简单的固定并发池：完成一个补一个，不做整批等待
    final queue = List.of(uploads);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final u = queue.removeAt(0);
        final f = byPath[u.path];
        if (f == null) continue;
        final data = await f.file.readAsBytes();
        await _put(Uri.parse(u.url), data, f.contentType);
        bytes += data.length;
        done++;
        onProgress?.call(done, total, u.path);
      }
    }

    await Future.wait([
      for (var i = 0; i < concurrency && i < uploads.length; i++) worker(),
    ]);

    return PublishResult(
      slug: created['slug'] as String,
      publicUrl: created['publicUrl'] as String,
      fileCount: files.length,
      totalBytes: bytes,
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
              '导出目录里有非 WebP 文件 ${p.basename(e.path)}，为安全起见拒绝上传');
        }
        out.add((
          path: '$sub/${p.basename(e.path)}',
          file: e,
          contentType: 'image/webp',
        ));
      }
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  Future<Map<String, dynamic>> _createStory(
      Object? manifest,
      List<({String path, File file, String contentType})> files,
      String visibility) async {
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
