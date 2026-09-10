import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

/// 已发布故事的列表 + 增删改。
///
/// 列表本身由 `tv_core` 的 `Publisher.listStories()` 拉；删除和重命名是
/// 这里补的两个直接调用 —— 服务器上那两个接口现在同时认会话 cookie
/// 和发布令牌，**手机上发出去的东西，得能在手机上删掉**。
class StoriesStore extends ChangeNotifier {
  StoriesStore(this.config);

  final PublishConfig config;

  List<RemoteStory>? stories;
  String? error;
  bool loading = false;

  String get _base => config.siteUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      stories = await Publisher(config).listStories();
    } on PublishException catch (e) {
      error = e.message;
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 封面：直接用公开页那个 Open Graph 图接口。
  ///
  /// 服务器的故事列表里没有封面字段，但每篇的分享预览图本来就有一个稳定地址，
  /// 拿它当列表封面是零成本的 —— **不用为了一张缩略图改服务器**。
  String coverUrl(RemoteStory s) => '${s.url}/opengraph-image';

  Future<bool> rename(RemoteStory s, String title) =>
      _patch(s, {'title': title});

  Future<bool> setVisibility(RemoteStory s, String v) =>
      _patch(s, {'visibility': v});

  Future<bool> _patch(RemoteStory s, Map<String, Object?> body) async {
    final ok = await _send('PATCH', '/api/stories/${s.id}', body);
    if (ok) await load();
    return ok;
  }

  Future<bool> remove(RemoteStory s) async {
    // 先从本地列表里拿掉，界面立刻有反应；失败了 load() 会把它放回来
    stories = stories?.where((e) => e.id != s.id).toList();
    notifyListeners();
    final ok = await _send('DELETE', '/api/stories/${s.id}', null);
    await load();
    return ok;
  }

  Future<bool> _send(String method, String path, Map<String, Object?>? body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.openUrl(method, Uri.parse('$_base$path'));
      req.headers.set('Authorization', 'Bearer ${config.token.trim()}');
      if (body != null) {
        req.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        req.write(jsonEncode(body));
      }
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      if (res.statusCode >= 400) {
        error = _errorOf(text, res.statusCode);
        notifyListeners();
        return false;
      }
      return true;
    } catch (e) {
      error = '$e';
      notifyListeners();
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static String _errorOf(String body, int code) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is String) return j['error'] as String;
    } catch (_) {}
    return '操作失败（HTTP $code）';
  }
}

/// 列表的排序方式。
enum StorySort { newest, oldest, mostPhotos }

extension StorySortX on StorySort {
  String get label => switch (this) {
        StorySort.newest => '最新在前',
        StorySort.oldest => '最早在前',
        StorySort.mostPhotos => '照片最多',
      };

  List<RemoteStory> apply(List<RemoteStory> list) {
    final out = [...list];
    switch (this) {
      case StorySort.newest:
        out.sort((a, b) => (b.publishedAt ?? '').compareTo(a.publishedAt ?? ''));
      case StorySort.oldest:
        out.sort((a, b) => (a.publishedAt ?? '').compareTo(b.publishedAt ?? ''));
      case StorySort.mostPhotos:
        out.sort((a, b) => b.photos.compareTo(a.photos));
    }
    return out;
  }
}
