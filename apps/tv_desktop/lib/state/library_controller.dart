import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:tv_core/tv_core.dart';

import '../native/native_bridge.dart';
import '../widgets/photo_tile.dart';

/// 桌面端的全部状态。业务逻辑一律在 tv_core 里，这里只负责调度和进度上报。
class LibraryController extends ChangeNotifier {
  Directory? _root;
  Catalog? _catalog;

  bool busy = false;
  String status = '';
  double? progress;
  List<LibraryIssue> issues = const [];
  String? lastError;

  ThumbnailCache? _thumbs;
  ThumbnailCache? get thumbs => _thumbs;

  Directory? get root => _root;
  Catalog? get catalog => _catalog;
  bool get hasLibrary => _catalog != null;
  int get photoCount => _catalog?.length ?? 0;

  int get gpsCount =>
      _catalog?.query(hasLocation: true).length ?? 0;

  int get totalBytes =>
      _catalog?.photos.fold<int>(0, (a, r) => a + r.bytes) ?? 0;

  /// 按日期倒序分组，最近的在最前面。
  List<MapEntry<String, List<PhotoRecord>>> get byDay {
    final map = <String, List<PhotoRecord>>{};
    for (final r in _catalog?.photos ?? const <PhotoRecord>[]) {
      map.putIfAbsent(LibraryLayout.dateStamp(r.takenAt), () => []).add(r);
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    for (final e in entries) {
      e.value.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    }
    return entries;
  }

  File fileOf(PhotoRecord r) {
    final rel = _catalog!.relPathOf(r.id)!;
    return File(p.joinAll([_root!.path, ...p.posix.split(rel)]));
  }

  Future<void> openLibrary(String path) async {
    await _guard('正在读取照片库...', () async {
      final dir = Directory(path);
      await Directory(p.join(dir.path, LibraryLayout.photosDir))
          .create(recursive: true);
      _root = dir;
      _catalog = Catalog(dir);
      _thumbs = ThumbnailCache(dir);
      final res = await _catalog!.rebuild();
      issues = res.issues;
      status = '已打开 ${res.photoCount} 张照片';
    });
  }

  /// 从一个文件夹导入。`tags` 用于给这批照片统一打标（例如"来自 iPhone 的这次旅行"）。
  Future<void> importFrom(String sourcePath, {List<Tag> tags = const []}) async {
    if (_catalog == null) return;
    await _guard('正在导入...', () async {
      final src = Directory(sourcePath);
      final files = <File>[];
      await for (final e in src.list(recursive: true, followLinks: false)) {
        if (e is File && !p.basename(e.path).startsWith('.')) files.add(e);
      }

      final importer = Importer(_catalog!);
      var imported = 0, dup = 0;
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        try {
          final meta = await NativeBridge.readMetadata(f.path);
          final stat = await f.stat();
          final r = await importer.importFile(
            f,
            // EXIF 拍摄时间才是真的；拿不到才退回文件修改时间
            takenAt: meta.takenAt ?? stat.modified,
            lat: meta.lat,
            lon: meta.lon,
            width: meta.width,
            height: meta.height,
            device: meta.device,
            tags: tags,
          );
          if (r.outcome == ImportOutcome.imported) {
            imported++;
          } else {
            dup++;
          }
        } catch (e) {
          lastError = '$e';
        }
        progress = (i + 1) / files.length;
        status = '正在导入 ${i + 1}/${files.length}';
        notifyListeners();
      }
      await _catalog!.writeJsonl();
      status = '导入完成: 新增 $imported 张，重复跳过 $dup 张';
    });
  }

  /// 从 iPhone 直接导入。
  ///
  /// **手机上的照片全程只读**: 只调下载，从不删除、从不修改。
  /// 流程是「下载到临时目录 -> 导入照片库 -> 删掉临时副本」，
  /// 删的是 Mac 上的中转文件，不是手机上的照片。
  Future<void> importFromPhone({
    required String deviceId,
    required List<String> names,
    List<Tag> tags = const [],
  }) async {
    if (_catalog == null) return;
    await _guard('正在从手机读取...', () async {
      final staging = await Directory(
        p.join(Directory.systemTemp.path,
            'travelview_staging_${DateTime.now().millisecondsSinceEpoch}'),
      ).create(recursive: true);

      NativeBridge.setDownloadProgressHandler((done, total, name, error) {
        progress = total == 0 ? null : done / total;
        status = '正在从手机读取 $done/$total  $name';
        if (error != null) lastError = error;
        notifyListeners();
      });

      try {
        final paths = await NativeBridge.downloadItems(
          deviceId: deviceId,
          names: names,
          destDir: staging.path,
        );

        status = '正在写入照片库...';
        notifyListeners();

        final importer = Importer(_catalog!);
        var imported = 0, dup = 0;
        for (var i = 0; i < paths.length; i++) {
          final f = File(paths[i]);
          if (!await f.exists()) continue;
          final meta = await NativeBridge.readMetadata(f.path);
          final stat = await f.stat();
          final r = await importer.importFile(
            f,
            takenAt: meta.takenAt ?? stat.modified,
            lat: meta.lat,
            lon: meta.lon,
            width: meta.width,
            height: meta.height,
            device: meta.device,
            tags: tags,
          );
          if (r.outcome == ImportOutcome.imported) {
            imported++;
          } else {
            dup++;
          }
          progress = (i + 1) / paths.length;
          status = '正在写入照片库 ${i + 1}/${paths.length}';
          notifyListeners();
        }
        await _catalog!.writeJsonl();
        final res = await _catalog!.rebuild();
        issues = res.issues;
        status = '从手机导入完成: 新增 $imported 张，已有 $dup 张';
      } finally {
        NativeBridge.setDownloadProgressHandler(null);
        // 只清理 Mac 上的中转副本
        if (await staging.exists()) {
          await staging.delete(recursive: true);
        }
      }
    });
  }

  Future<void> rebuild() async {
    if (_catalog == null) return;
    await _guard('正在重建索引...', () async {
      final res = await _catalog!.rebuild();
      issues = res.issues;
      await _catalog!.writeJsonl();
      status = '重建完成: ${res.photoCount} 张照片，${res.issues.length} 个待处理项';
    });
  }

  Future<void> verify() async {
    if (_catalog == null) return;
    await _guard('正在校验...', () async {
      final report = await Verifier(_catalog!).run(onProgress: (d, t) {
        progress = t == 0 ? null : d / t;
        status = '正在校验 $d/$t';
        notifyListeners();
      });
      issues = report.problems;
      status = report.ok
          ? '校验通过: ${report.checked} 张照片全部完好'
          : '校验发现 ${report.problems.length} 个问题';
    });
  }

  Future<void> _guard(String label, Future<void> Function() body) async {
    busy = true;
    progress = null;
    lastError = null;
    status = label;
    notifyListeners();
    try {
      await body();
    } catch (e) {
      lastError = '$e';
      status = '出错了';
    } finally {
      busy = false;
      progress = null;
      notifyListeners();
    }
  }
}

String humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024.0;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}
