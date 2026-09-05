import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'fingerprint.dart';
import 'layout.dart';
import 'models.dart';
import 'sidecar.dart';

/// 扫描库时发现的异常。
class LibraryIssue {
  final String kind; // orphan | missing | mismatch | adopted
  final String path;
  final String detail;
  const LibraryIssue(this.kind, this.path, this.detail);
  @override
  String toString() => '[$kind] $path — $detail';
}

class RebuildResult {
  final int photoCount;
  final int dayDirCount;
  final List<LibraryIssue> issues;
  const RebuildResult(this.photoCount, this.dayDirCount, this.issues);
}

/// 派生索引。**可以随时整个删掉重建** —— 这是原则 3 的可执行证明。
///
/// 第一版用内存索引 + JSONL 镜像，不引入 SQLite:
/// 架构上 catalog 本来就只是缓存，先把"真相层"做扎实，
/// 等照片量级真的需要毫秒级查询时再挂 SQLite，接口不变。
class Catalog {
  final Directory root;
  final Map<String, PhotoRecord> _byId = {};
  final Map<String, String> _pathById = {}; // id -> 库内相对路径

  Catalog(this.root);

  Iterable<PhotoRecord> get photos => _byId.values;
  int get length => _byId.length;

  PhotoRecord? byId(String id) => _byId[id];
  String? relPathOf(String id) => _pathById[id];

  Directory get photosRoot =>
      Directory(p.join(root.path, LibraryLayout.photosDir));

  /// 从文件树 + sidecar 完整重建索引。
  ///
  /// 自愈的核心: 目录里有文件但 sidecar 没记（orphan），就算它的内容哈希，
  /// 如果这个 id 在别处见过，说明用户只是改了名/挪了位置 —— 认领回来，
  /// 而不是当成新照片重复导入。
  Future<RebuildResult> rebuild({bool hashOrphans = true}) async {
    _byId.clear();
    _pathById.clear();
    final issues = <LibraryIssue>[];
    var dayDirs = 0;

    if (!await photosRoot.exists()) {
      return RebuildResult(0, 0, issues);
    }

    final orphanFiles = <File>[];

    await for (final entity in photosRoot.list(recursive: true)) {
      if (entity is! Directory) continue;
      final sidecarFile = Sidecar.fileFor(entity);
      final files = await _mediaFilesIn(entity);
      if (!await sidecarFile.exists() && files.isEmpty) continue;
      dayDirs++;

      final sc = await Sidecar.load(entity);
      final seen = <String>{};

      for (final f in files) {
        final name = p.basename(f.path);
        final rec = sc.photos[name];
        if (rec == null) {
          orphanFiles.add(f);
          continue;
        }
        seen.add(name);
        _register(rec, f);
      }

      for (final name in sc.photos.keys) {
        if (!seen.contains(name)) {
          issues.add(LibraryIssue(
              'missing', p.join(entity.path, name), 'sidecar 有记录但文件不在'));
        }
      }
    }

    // 第二遍处理孤儿文件: 靠内容哈希认领
    for (final f in orphanFiles) {
      if (!hashOrphans) {
        issues.add(LibraryIssue('orphan', f.path, '文件存在但 sidecar 无记录'));
        continue;
      }
      final id = await Fingerprint.contentId(f);
      final known = _byId[id];
      if (known != null) {
        issues.add(LibraryIssue(
            'adopted', f.path, '按内容哈希认出是已知照片 ${known.origFilename}'));
      } else {
        issues.add(LibraryIssue('orphan', f.path, '未登记的新文件，需 import'));
      }
    }

    return RebuildResult(_byId.length, dayDirs, issues);
  }

  /// 供 Importer 在写完 sidecar 之后同步内存索引。
  /// 注意: 调用方必须先把同样的信息写进 sidecar（sidecar 才是真相）。
  void absorb(PhotoRecord rec, String relPath) {
    relPath = toPosix(relPath);
    final existing = _byId[rec.id];
    _byId[rec.id] = existing == null ? rec : existing.mergeWith(rec);
    _pathById[rec.id] = relPath;
  }

  /// 库可能放在移动硬盘上，被 Mac 和 Windows 轮流读写，
  /// 所以索引里的路径一律用 / 分隔，不能带平台相关的 \。
  static String toPosix(String relPath) => p.posix.joinAll(p.split(relPath));

  void _register(PhotoRecord rec, File f) {
    final rel = toPosix(p.relative(f.path, from: root.path));
    final existing = _byId[rec.id];
    _byId[rec.id] = existing == null ? rec : existing.mergeWith(rec);
    _pathById[rec.id] = rel;
  }

  static Future<List<File>> _mediaFilesIn(Directory dir) async {
    final out = <File>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue; // sidecar 和 macOS 的 ._ 文件
      if (name.endsWith('.tmp')) continue;
      out.add(e);
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  // ---- 打标签: 挑选、分组、归属旅行，都是同一件事 ----

  /// 给一张照片加上或去掉一个 tag。
  ///
  /// 先写 sidecar（真相），再更新内存索引 —— 顺序不能反。
  /// 返回更新后的记录；照片不在库里时返回 null。
  Future<PhotoRecord?> setTag(
    String photoId,
    Tag tag, {
    required bool on,
  }) async {
    final rec = _byId[photoId];
    final rel = _pathById[photoId];
    if (rec == null || rel == null) return null;

    final file = File(p.joinAll([root.path, ...p.posix.split(rel)]));
    final dayDir = file.parent;
    final fileName = p.basename(file.path);

    final tags = rec.tags.toList();
    final has = tags.contains(tag);
    if (on == has) return rec; // 没有变化，不写盘
    if (on) {
      tags.add(tag);
    } else {
      tags.removeWhere((t) => t == tag);
    }

    final updated = rec.copyWith(tags: tags);
    final sc = await Sidecar.load(dayDir);
    sc.replace(fileName, updated);
    await sc.save(dayDir);

    _byId[photoId] = updated;
    return updated;
  }

  // ---- 查询: 所有"分类"都是对 tag 的查询，零文件副本 ----

  List<PhotoRecord> query({
    String? tagKind,
    String? tagValue,
    int? year,
    bool? hasLocation,
  }) {
    final out = photos.where((r) {
      if (year != null && r.takenAt.year != year) return false;
      if (hasLocation != null && r.hasLocation != hasLocation) return false;
      if (tagKind != null) {
        final match = r.tags.any((t) =>
            t.kind == tagKind && (tagValue == null || t.value == tagValue));
        if (!match) return false;
      }
      return true;
    }).toList();
    out.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    return out;
  }

  /// 某个维度下有哪些取值，各多少张。用来渲染视图的导航。
  Map<String, int> facet(String tagKind) {
    final counts = <String, int>{};
    for (final r in photos) {
      for (final t in r.tags) {
        if (t.kind == tagKind) {
          counts[t.value] = (counts[t.value] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  // ---- JSONL 文本镜像: 可 grep、可进 git、可 diff ----

  File get jsonlFile => File(
      p.join(root.path, LibraryLayout.catalogDir, LibraryLayout.catalogJsonl));

  Future<void> writeJsonl() async {
    final f = jsonlFile;
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    final sink = tmp.openWrite();
    final sorted = photos.toList()
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    for (final r in sorted) {
      final line = {...r.toJson(), 'path': _pathById[r.id]};
      sink.writeln(jsonEncode(line));
    }
    await sink.flush();
    await sink.close();
    await tmp.rename(f.path);
  }
}
