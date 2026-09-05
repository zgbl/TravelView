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

  /// 全局时间范围筛选。
  ///
  /// **筛选是"看"的方式，不是"存"的方式** —— 照片库永远只有一个、装全部照片，
  /// 想做哪段行程的报告就把范围调到哪段，照片视图和行程地图同时跟着变。
  /// 绝不需要为了做某次旅行的报告，把照片再导一份到新文件夹。
  DateTime? rangeStart;
  DateTime? rangeEnd;

  bool get hasRange => rangeStart != null || rangeEnd != null;

  void setRange(DateTime? from, DateTime? to) {
    rangeStart = from == null ? null : DateTime(from.year, from.month, from.day);
    rangeEnd = to == null
        ? null
        : DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
    _invalidate();
    notifyListeners();
  }

  void clearRange() => setRange(null, null);

  bool inRange(PhotoRecord r) {
    if (rangeStart != null && r.takenAt.isBefore(rangeStart!)) return false;
    if (rangeEnd != null && !r.takenAt.isBefore(rangeEnd!)) return false;
    return true;
  }

  /// 当前范围内的照片。所有视图都用它，保证照片和地图看到的是同一批。
  List<PhotoRecord> get visiblePhotos {
    final all = _catalog?.photos ?? const <PhotoRecord>[];
    if (!hasRange) return all.toList();
    return all.where(inRange).toList();
  }

  int get visibleCount => visiblePhotos.length;

  /// 库里照片的时间跨度，用来给日期选择器一个合理的初始范围
  (DateTime, DateTime)? get libraryTimeSpan {
    final all = _catalog?.photos;
    if (all == null || all.isEmpty) return null;
    var min = all.first.takenAt, max = all.first.takenAt;
    for (final r in all) {
      if (r.takenAt.isBefore(min)) min = r.takenAt;
      if (r.takenAt.isAfter(max)) max = r.takenAt;
    }
    return (min, max);
  }

  /// 当前正在挑选的专辑名。选取只是打一个 tag，
  /// **不选取不等于删除** —— 照片一直在库里，只是没进这个专辑。
  String pickAlbum = '精选';

  ThumbnailWarmer? _warmer;
  int warmDone = 0;
  int warmTotal = 0;

  /// 后台预热进度。注意它**不占用** busy —— 预热期间所有操作照常可用。
  bool get warming => warmTotal > 0 && warmDone < warmTotal;

  Directory? get root => _root;
  Catalog? get catalog => _catalog;
  bool get hasLibrary => _catalog != null;
  int get photoCount => _catalog?.length ?? 0;

  int get gpsCount =>
      _catalog?.query(hasLocation: true).length ?? 0;

  int get totalBytes =>
      _catalog?.photos.fold<int>(0, (a, r) => a + r.bytes) ?? 0;

  List<MapEntry<String, List<PhotoRecord>>>? _byDayCache;

  /// 按日期倒序分组，最近的在最前面。
  /// **必须缓存**: 每次 build 都对几千张照片重新分组会明显拖慢界面。
  /// 库内容变化时调 _invalidate() 失效。
  List<MapEntry<String, List<PhotoRecord>>> get byDay {
    final cached = _byDayCache;
    if (cached != null) return cached;
    final map = <String, List<PhotoRecord>>{};
    for (final r in visiblePhotos) {
      map.putIfAbsent(LibraryLayout.dateStamp(r.takenAt), () => []).add(r);
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    for (final e in entries) {
      e.value.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    }
    _byDayCache = entries;
    return entries;
  }

  void _invalidate() => _byDayCache = null;

  File fileOf(PhotoRecord r) {
    final rel = _catalog!.relPathOf(r.id)!;
    return File(p.joinAll([_root!.path, ...p.posix.split(rel)]));
  }

  Tag get _pickTag => Tag('pick', pickAlbum);

  bool isPicked(PhotoRecord r) => r.tags.contains(_pickTag);

  int get pickedCount =>
      _catalog?.query(tagKind: 'pick', tagValue: pickAlbum).length ?? 0;

  /// 切换选取。写 sidecar 是真相，内存索引跟着更新。
  /// 返回切换后的状态，供 UI 立即反馈。
  Future<bool> togglePick(PhotoRecord r) async {
    final want = !isPicked(r);
    await setPicked(r, want);
    return want;
  }

  Future<void> setPicked(PhotoRecord r, bool on) async {
    final cat = _catalog;
    if (cat == null) return;
    final live = cat.byId(r.id) ?? r;
    if (isPicked(live) == on) return;
    await cat.setTag(r.id, _pickTag, on: on);
    // byDay 缓存里存的是旧的记录对象，不失效的话界面看不到选中状态
    _invalidate();
    notifyListeners();
  }

  /// 旋转照片 90 度，直接写回原文件。
  ///
  /// 只改 EXIF 方向标记，不重新编码，所以画质无损、拍摄时间不变。
  /// 但内容变了意味着**内容哈希变了**，id 会更新 —— 标签会完整保留。
  /// 返回新的 id（失败时返回 null）。
  Future<String?> rotate(PhotoRecord r, {bool clockwise = true}) async {
    final cat = _catalog;
    final th = _thumbs;
    if (cat == null || th == null) return null;
    final file = fileOf(r);

    final err = await NativeBridge.rotate(file.path, clockwise: clockwise);
    if (err != null) {
      lastError = err;
      notifyListeners();
      return null;
    }

    // 旋转后宽高互换，重新读一次元数据
    final meta = await NativeBridge.readMetadata(file.path);
    final updated = await cat.refreshAfterEdit(
      r.id,
      width: meta.width,
      height: meta.height,
    );
    if (updated == null) return null;

    // 旧的派生图作废
    for (final variant in ['thumbs', 'previews']) {
      final f = th.pathFor(r.id, variant: variant);
      if (await f.exists()) await f.delete();
    }
    _invalidate();
    notifyListeners();
    return updated.id;
  }

  void setPickAlbum(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == pickAlbum) return;
    pickAlbum = trimmed;
    notifyListeners();
  }

  Future<void> openLibrary(String path) async {
    await _guard('正在读取照片库...', () async {
      final dir = Directory(path);
      await Directory(p.join(dir.path, LibraryLayout.photosDir))
          .create(recursive: true);
      _warmer?.cancel();
      _root = dir;
      _catalog = Catalog(dir);
      _thumbs = ThumbnailCache(dir);
      final res = await _catalog!.rebuild();
      issues = res.issues;
      status = '已打开 ${res.photoCount} 张照片';
    });
    startWarming();
  }

  /// 后台把缩略图全部生成好，让浏览时不再有等待。
  /// 按界面显示顺序（最近的日期在前）预热，等待感最小。
  void startWarming() {
    final cat = _catalog, th = _thumbs;
    if (cat == null || th == null) return;
    _warmer?.cancel();
    final items = <MapEntry<String, File>>[];
    for (final day in byDay) {
      for (final r in day.value) {
        items.add(MapEntry(r.id, fileOf(r)));
      }
    }
    if (items.isEmpty) return;
    warmDone = 0;
    warmTotal = items.length;
    _warmer = ThumbnailWarmer(
      cache: th,
      onProgress: (done, total) {
        warmDone = done;
        warmTotal = total;
        notifyListeners();
      },
    );
    // 不 await —— 预热在后台跑，前台该干嘛干嘛
    _warmer!.run(items);
  }

  @override
  void dispose() {
    _warmer?.cancel();
    super.dispose();
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
      _invalidate();
      startWarming();
    });
  }

  /// 从 iPhone 直接导入。
  ///
  /// **手机上的照片全程只读**: 只调下载，从不删除、从不修改。
  /// 流程是「下载到临时目录 -> 导入照片库 -> 删掉临时副本」，
  /// 删的是 Mac 上的中转文件，不是手机上的照片。
  /// 从 iPhone 直接导入。
  ///
  /// **手机上的照片全程只读**: 只调下载，从不删除、从不修改。
  /// 流程是「下载到临时目录 -> 导入照片库 -> 删掉临时副本」，
  /// 删的是 Mac 上的中转文件，不是手机上的照片。
  ///
  /// [keys] 是 PhoneItem.key（文件夹路径+文件名），不能用裸文件名 ——
  /// iPhone 的 DCIM 分多个文件夹且文件名会绕回重复。
  /// [limitFrom]/[limitUntil] 是最后一道防线: 即使设备侧筛错了，
  /// 按 EXIF 拍摄时间再挡一次。传日期即可，内部按自然日取整。
  /// 这里刻意不用 DateTimeRange —— 那是 material 的类型，
  /// 状态层不该依赖 widget 库。
  Future<void> importFromPhone({
    required String deviceId,
    required List<String> keys,
    DateTime? limitFrom,
    DateTime? limitUntil,
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
        final files = await NativeBridge.downloadItems(
          deviceId: deviceId,
          keys: keys,
          destDir: staging.path,
        );

        status = '正在写入照片库...';
        notifyListeners();

        final from = limitFrom == null
            ? null
            : DateTime(limitFrom.year, limitFrom.month, limitFrom.day);
        final to = limitUntil == null
            ? null
            : DateTime(limitUntil.year, limitUntil.month, limitUntil.day)
                .add(const Duration(days: 1));

        final importer = Importer(_catalog!);
        var imported = 0, dup = 0, skipped = 0;
        for (var i = 0; i < files.length; i++) {
          final f = File(files[i].path);
          if (!await f.exists()) continue;
          final meta = await NativeBridge.readMetadata(f.path);
          final stat = await f.stat();
          final takenAt = meta.takenAt ?? stat.modified;

          // 兜底: 拍摄时间落在选定范围外的一律不入库
          if ((from != null && takenAt.isBefore(from)) ||
              (to != null && !takenAt.isBefore(to))) {
            skipped++;
            continue;
          }

          final r = await importer.importFile(
            f,
            takenAt: takenAt,
            lat: meta.lat,
            lon: meta.lon,
            width: meta.width,
            height: meta.height,
            device: meta.device,
            origFilename: files[i].origName,
            tags: tags,
          );
          if (r.outcome == ImportOutcome.imported) {
            imported++;
          } else {
            dup++;
          }
          progress = (i + 1) / files.length;
          status = '正在写入照片库 ${i + 1}/${files.length}';
          notifyListeners();
        }
        await _catalog!.writeJsonl();
        final res = await _catalog!.rebuild();
        issues = res.issues;
        status = skipped > 0
            ? '从手机导入完成: 新增 $imported 张，已有 $dup 张，'
                '$skipped 张不在所选日期范围内已跳过'
            : '从手机导入完成: 新增 $imported 张，已有 $dup 张';
        _invalidate();
        startWarming();
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
    _invalidate();
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
      _invalidate();
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
