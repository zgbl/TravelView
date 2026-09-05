import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'layout.dart';
import 'models.dart';

/// 每个日期目录一个 `.tvmeta.json` —— **这是元数据的真相**。
///
/// 它跟着照片走: 用户把某个文件夹拷到别处，元数据一起走。
/// catalog（SQLite / JSONL）只是从这些文件派生出来的缓存，随时可以删掉重建。
///
/// 硬约束: 任何写进 catalog 的信息，必须同时落进对应的 sidecar。
/// catalog 里永远不允许存在唯一一份的信息。
class Sidecar {
  static const int formatVersion = 1;

  final String dirName;
  final Map<String, PhotoRecord> photos;

  Sidecar({required this.dirName, Map<String, PhotoRecord>? photos})
      : photos = photos ?? <String, PhotoRecord>{};

  /// 文件名 -> 记录。sidecar 里同时保留文件名，是为了在哈希之前就能
  /// 快速判断"这个目录有没有变过"。
  static File fileFor(Directory dayDir) =>
      File(p.join(dayDir.path, LibraryLayout.sidecarName));

  static Future<Sidecar> load(Directory dayDir) async {
    final f = fileFor(dayDir);
    if (!await f.exists()) {
      return Sidecar(dirName: p.basename(dayDir.path));
    }
    final raw = await f.readAsString();
    if (raw.trim().isEmpty) {
      return Sidecar(dirName: p.basename(dayDir.path));
    }
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final entries = (j['photos'] as Map<String, dynamic>? ?? {});
    final photos = <String, PhotoRecord>{};
    entries.forEach((fileName, v) {
      photos[fileName] =
          PhotoRecord.fromJson(Map<String, dynamic>.from(v as Map));
    });
    return Sidecar(
      dirName: j['dir'] as String? ?? p.basename(dayDir.path),
      photos: photos,
    );
  }

  /// 原子写入: 先写 .tmp 再 rename，断电不会留下半个文件。
  Future<void> save(Directory dayDir) async {
    await dayDir.create(recursive: true);
    final target = fileFor(dayDir);
    final tmp = File('${target.path}.tmp');
    final data = {
      'version': formatVersion,
      'dir': dirName,
      'generator': 'TravelView tv_core',
      'photos': {
        for (final e in _sortedEntries()) e.key: e.value.toJson(),
      },
    };
    await tmp.writeAsString('${prettyJson(data)}\n', flush: true);
    await tmp.rename(target.path);
  }

  List<MapEntry<String, PhotoRecord>> _sortedEntries() {
    final list = photos.entries.toList();
    list.sort((a, b) => a.key.compareTo(b.key));
    return list;
  }

  /// 按 id 查文件名（自愈时用: 文件被改名了，靠 id 找回它的元数据）
  String? fileNameOf(String photoId) {
    for (final e in photos.entries) {
      if (e.value.id == photoId) return e.key;
    }
    return null;
  }

  void put(String fileName, PhotoRecord rec) {
    final existingName = fileNameOf(rec.id);
    if (existingName != null && existingName != fileName) {
      // 同一张照片换了文件名: 搬过去，合并元数据，绝不留两条
      final old = photos.remove(existingName)!;
      photos[fileName] = old.mergeWith(rec);
      return;
    }
    final prev = photos[fileName];
    photos[fileName] = prev == null ? rec : prev.mergeWith(rec);
  }

  /// 直接覆盖，不做合并。
  ///
  /// [put] 会把新旧记录取并集（导入时不能丢信息），
  /// 但**取消选取**这类操作必须能真的删掉一个 tag，所以需要这条路径。
  void replace(String fileName, PhotoRecord rec) {
    final existingName = fileNameOf(rec.id);
    if (existingName != null && existingName != fileName) {
      photos.remove(existingName);
    }
    photos[fileName] = rec;
  }

  bool get isEmpty => photos.isEmpty;
}
