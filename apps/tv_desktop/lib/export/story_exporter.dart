import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tv_core/tv_core.dart';

import '../native/native_bridge.dart';
import 'web_template.dart';

class ExportResult {
  final Directory dir;
  final File indexHtml;
  final int photoCount;
  final int totalBytes;
  final List<String> warnings;

  /// **这一份产物是哪一趟行程**的指纹: 起止日期 + 站数 + 照片数。
  ///
  /// 发布时把它记在草稿上。下次要判断"这次发的还是不是网站上那一篇"，
  /// 靠它来比，**不能靠草稿的名字** —— 用户在同一个草稿里换个时间范围
  /// 做的就是另一趟行程了，名字却一点没变。
  /// 认错了的代价是把上一篇直接覆盖掉，所以这里宁可判成"不是同一篇"。
  final String storyKey;

  const ExportResult({
    required this.dir,
    required this.indexHtml,
    required this.photoCount,
    required this.totalBytes,
    required this.warnings,
    this.storyKey = '',
  });
}

/// 把当前的行程导出成一个**完整、自包含、可离线打开**的 Story 网页包。
///
/// 产物目录:
/// ```
/// <库>/views/by-trip/<slug>/
///   index.html        渲染器（单文件，无需构建）
///   story.json        manifest
///   photos/*.webp     网页用派生图（1600px，已剥 EXIF）
///   thumbs/*.webp     缩略图
/// ```
///
/// **原图一张都不复制进去。** 这个目录就是将来要上传的全部内容 ——
/// 先在本地跑通，再谈服务器。
class StoryExporter {
  final Directory libraryRoot;
  final Catalog catalog;

  StoryExporter({required this.libraryRoot, required this.catalog});

  Future<ExportResult> export({
    required TripRoute trip,
    required Set<String> selectedIds,
    required Map<int, String?> heroByStopSeq,
    String? coverPhotoId,
    required List<RouteLeg> legs,
    required String title,
    String? subtitle,
    Map<int, String>? stopNames,
    Map<int, String>? stopNotes,
    String slug = '',
    int webMaxPixels = 1600,
    int thumbMaxPixels = 480,
    void Function(int done, int total, String label)? onProgress,
  }) async {
    final theSlug = slug.isEmpty ? _slugFor(title) : slug;
    final dir = Directory(p.join(libraryRoot.path, LibraryLayout.viewsDir,
        'by-trip', theSlug));
    await Directory(p.join(dir.path, 'photos')).create(recursive: true);
    await Directory(p.join(dir.path, 'thumbs')).create(recursive: true);

    final warnings = <String>[];
    final records = <String, PhotoRecord>{};
    final exported = <String, ExportedImage>{};
    final thumbs = <String, String>{};

    // 只导出被选中的照片
    final wanted = <PhotoRecord>[];
    for (final stop in trip.stays) {
      for (final id in stop.photoIds) {
        if (!selectedIds.contains(id)) continue;
        final r = catalog.byId(id);
        if (r != null) wanted.add(r);
      }
    }

    var done = 0;
    var totalBytes = 0;
    for (final r in wanted) {
      final rel = catalog.relPathOf(r.id);
      if (rel == null) {
        warnings.add('${r.origFilename}: 库里找不到文件');
        continue;
      }
      final src = File(p.joinAll([libraryRoot.path, ...p.posix.split(rel)]));

      final web = await NativeBridge.exportWeb(
        src.path,
        p.join(dir.path, 'photos', '${r.id}.webp'),
        maxPixels: webMaxPixels,
      );
      if (web == null) {
        warnings.add('${r.origFilename}: 导出失败');
        done++;
        onProgress?.call(done, wanted.length, r.origFilename);
        continue;
      }
      // 缩略图也可能退回 JPEG，路径必须用**实际导出的文件名**，
      // 不能写死 .webp —— 写死的话 manifest 会指向一个不存在的文件
      final thumb = await NativeBridge.exportWeb(
        src.path,
        p.join(dir.path, 'thumbs', '${r.id}.webp'),
        maxPixels: thumbMaxPixels,
        quality: 0.72,
      );
      thumbs[r.id] = thumb == null
          ? 'thumbs/${r.id}.webp'
          : 'thumbs/${p.basename(thumb.path)}';

      records[r.id] = r;
      exported[r.id] = web;
      totalBytes += web.bytes;
      done++;
      onProgress?.call(done, wanted.length, r.origFilename);
    }

    // 用实际导出的尺寸和文件名装配 Story
    final story = StoryBuilder.build(
      id: theSlug,
      slug: theSlug,
      title: title,
      subtitle: subtitle,
      trip: trip,
      recordsById: records,
      selectedIds: records.keys.toSet(),
      heroByStopSeq: heroByStopSeq,
      coverPhotoId: coverPhotoId,
      legs: legs,
      webPathOf: (r) => 'photos/${p.basename(exported[r.id]!.path)}',
      thumbPathOf: (r) => thumbs[r.id] ?? 'thumbs/${r.id}.webp',
      stopNames: stopNames,
      stopNotes: stopNotes,
    );

    // 派生图的真实宽高要覆盖回 manifest，否则网页布局会跳
    final fixedPhotos = story.photos.map((sp) {
      final e = exported[sp.id];
      if (e == null) return sp;
      return StoryPhoto(
        id: sp.id,
        takenAt: sp.takenAt,
        lat: sp.lat,
        lon: sp.lon,
        webPath: sp.webPath,
        webWidth: e.width,
        webHeight: e.height,
        thumbPath: sp.thumbPath,
        caption: sp.caption,
      );
    }).toList();

    final finalStory = Story(
      id: story.id,
      slug: story.slug,
      title: story.title,
      subtitle: story.subtitle,
      start: story.start,
      end: story.end,
      coverPhotoId: story.coverPhotoId,
      template: story.template,
      days: story.days,
      stops: story.stops,
      photos: fixedPhotos,
      routes: story.routes,
    );

    // ── 分享预览图 og.jpg ──
    // **必须是 JPEG**: Facebook / 微信的抓取器和 next/og 都不解 WebP，
    // 塞一张 WebP 过去，分享出来就是一大块白。
    // 单独生成一张 1200px 的封面图，不复用 photos/ 里那张。
    String? ogImage;
    final coverId = finalStory.coverPhotoId ??
        (fixedPhotos.isEmpty ? null : fixedPhotos.first.id);
    final coverRel = coverId == null ? null : catalog.relPathOf(coverId);
    if (coverRel != null) {
      final og = await NativeBridge.exportWeb(
        File(p.joinAll([libraryRoot.path, ...p.posix.split(coverRel)])).path,
        p.join(dir.path, 'og.jpg'),
        maxPixels: 1200,
        quality: 0.85,
        forceJpeg: true,
      );
      if (og != null) ogImage = 'og.jpg';
    }

    final manifest = File(p.join(dir.path, 'story.json'));
    final manifestJson = finalStory.toJson();
    if (ogImage != null) manifestJson['ogImage'] = ogImage;
    await manifest.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifestJson));

    final indexHtml = File(p.join(dir.path, 'index.html'));
    await indexHtml.writeAsString(buildStoryHtml(finalStory));

    return ExportResult(
      dir: dir,
      indexHtml: indexHtml,
      photoCount: finalStory.photoCount,
      totalBytes: totalBytes,
      warnings: warnings,
      storyKey: [
        finalStory.start.toIso8601String().substring(0, 10),
        finalStory.end.toIso8601String().substring(0, 10),
        finalStory.stops.length,
        finalStory.photos.length,
      ].join('|'),
    );
  }

  static String _slugFor(String title) {
    final ascii = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stamp = DateTime.now().millisecondsSinceEpoch
        .toRadixString(36)
        .substring(4);
    return ascii.isEmpty ? 'trip-$stamp' : '$ascii-$stamp';
  }
}
