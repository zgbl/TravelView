import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:tv_core/tv_core.dart';

import 'l10n.dart';

/// 一篇能**在 App 里直接看**的行程。
///
/// manifest（story.json）里存的永远是 `photos/x.webp` 这样的相对路径 ——
/// 同一份 manifest 在导出目录里、在服务器上都成立，差别只有"相对谁"。
/// 这个类就只解决这一件事：把相对路径变成阅读器能直接喂给 Image 的东西。
///
/// **两个来源用同一个类。** 本地导出的产物和已发布的故事，
/// 对阅读器来说必须是同一样东西，否则阅读器要写两遍。
class StoryBundle {
  final Story story;

  /// 本地导出目录。远端来源时为 null。
  final Directory? dir;

  /// 远端媒体根（已经带上这篇的前缀）。本地来源时为 null。
  final Uri? mediaBase;

  /// 分享出去的公开链接。本地还没发布的产物没有这个。
  final String? shareUrl;

  /// 片头用路线图还是照片，以及距离单位。都是 manifest 上 Story 之外的字段。
  final String coverMode;
  final String units;

  const StoryBundle({
    required this.story,
    this.dir,
    this.mediaBase,
    this.shareUrl,
    this.coverMode = 'auto',
    this.units = 'auto',
  });

  bool get isRemote => mediaBase != null;

  /// 距离单位。'auto' 时按第一站的经纬度粗判美国 ——
  /// **和网页那份规则保持一致**，同一篇游记在两个地方不能显示不同的数字。
  bool get useMiles {
    if (units == 'mi') return true;
    if (units == 'km') return false;
    final s = story.stops.isEmpty ? null : story.stops.first;
    if (s == null) return false;
    return s.lat > 24 && s.lat < 50 && s.lon > -125 && s.lon < -66;
  }

  ImageProvider image(String relPath) {
    final rel = relPath.replaceFirst(RegExp(r'^/+'), '');
    final base = mediaBase;
    if (base != null) {
      return NetworkImage(base.toString().replaceAll(RegExp(r'/+$'), '') + '/' + rel);
    }
    return FileImage(File(p.join(dir!.path, rel)));
  }

  /// 网格里用缩略图（480px）。**不要拿 1600px 的大图去填格子** ——
  /// 一篇一百多张照片的游记，网格全用大图就是几十兆的无谓流量和内存。
  ImageProvider thumb(StoryPhoto photo) =>
      image(photo.thumbPath ?? photo.webPath);

  ImageProvider full(StoryPhoto photo) => image(photo.webPath);

  StoryPhoto? photoById(String? id) {
    if (id == null) return null;
    for (final p in story.photos) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 封面那张。指定了就用指定的，没指定就用第一张 —— 永远有图，不留白。
  StoryPhoto? get coverPhoto =>
      photoById(story.coverPhotoId) ??
      (story.photos.isEmpty ? null : story.photos.first);

  // ── 打开 ──

  /// 打开一份本地导出产物（`<dir>/story.json`）。
  static Future<StoryBundle> openDirectory(Directory dir,
      {String? shareUrl}) async {
    final f = File(p.join(dir.path, 'story.json'));
    if (!await f.exists()) {
      throw StoryBundleException(tr('这份产物里没有 story.json'));
    }
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return StoryBundle(
      story: Story.fromJson(j),
      dir: dir,
      shareUrl: shareUrl,
      coverMode: j['coverMode'] as String? ?? 'auto',
      units: j['units'] as String? ?? 'auto',
    );
  }

  /// 打开一篇已发布的故事。
  ///
  /// 公开页在 `<站点>/s/<slug>` 旁边给了一份 `story.json` ——
  /// 它比网页多一个 `mediaBase`，因为服务器上的图不和 manifest 放在一起。
  /// **不要去解析那个网页**：页面结构一改，App 就瞎了。
  static Future<StoryBundle> openUrl(String storyUrl) async {
    final base = storyUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/story.json');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      if (res.statusCode == 404) {
        throw StoryBundleException(tr('这篇故事打不开了（可能已被删除或设为私密）'));
      }
      if (res.statusCode >= 400) {
        throw StoryBundleException(trf('取不到这篇故事（HTTP {0}）', [res.statusCode]));
      }
      final j = jsonDecode(text) as Map<String, dynamic>;
      final media = (j['mediaBase'] as String?)?.trim();
      if (media == null || media.isEmpty) {
        throw StoryBundleException(tr('这篇故事的图片地址不完整'));
      }
      return StoryBundle(
        story: Story.fromJson(j),
        mediaBase: Uri.parse(media),
        shareUrl: base,
        coverMode: j['coverMode'] as String? ?? 'auto',
        units: j['units'] as String? ?? 'auto',
      );
    } on SocketException catch (e) {
      throw StoryBundleException(trf('连不上服务器: {0}', [e.message]));
    } finally {
      client.close(force: true);
    }
  }
}

class StoryBundleException implements Exception {
  final String message;
  const StoryBundleException(this.message);
  @override
  String toString() => message;
}
