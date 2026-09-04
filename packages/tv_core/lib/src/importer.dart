import 'dart:io';

import 'package:path/path.dart' as p;

import 'catalog.dart';
import 'fingerprint.dart';
import 'layout.dart';
import 'models.dart';
import 'sidecar.dart';

enum ImportOutcome { imported, duplicate, updated }

class ImportResult {
  final ImportOutcome outcome;
  final PhotoRecord record;
  final String relPath;
  const ImportResult(this.outcome, this.record, this.relPath);
}

/// 把一个源文件导入库。
///
/// 铁律:
///   - 只读源文件，永不修改、永不删除
///   - 目标位置已有文件时，永不覆盖
///   - 同一内容重复导入是幂等的，只补元数据，不产生第二份字节
class Importer {
  final Catalog catalog;

  Importer(this.catalog);

  Future<ImportResult> importFile(
    File source, {
    required DateTime takenAt,
    double? lat,
    double? lon,
    String? device,
    String? mime,
    int? width,
    int? height,
    bool isScreenshot = false,
    List<Tag> tags = const [],
    String? origFilename,
  }) async {
    final id = await Fingerprint.contentId(source);
    final bytes = await source.length();
    final name = origFilename ?? p.basename(source.path);

    final incoming = PhotoRecord(
      id: id,
      takenAt: takenAt,
      bytes: bytes,
      origFilename: name,
      lat: lat,
      lon: lon,
      width: width,
      height: height,
      mime: mime,
      device: device,
      isScreenshot: isScreenshot,
      tags: tags,
    );

    // 已在库里: 不复制字节，只把新元数据并进去（原则 2）
    final existingRel = catalog.relPathOf(id);
    if (existingRel != null) {
      final existingFile = File(p.join(catalog.root.path, existingRel));
      final dayDir = existingFile.parent;
      final sc = await Sidecar.load(dayDir);
      final before = catalog.byId(id)!;
      final merged = before.mergeWith(incoming);
      // 先判断有没有新信息，再落盘 —— 顺序反了就永远判为 duplicate
      final changed =
          merged.toJson().toString() != before.toJson().toString();
      sc.put(p.basename(existingFile.path), merged);
      await sc.save(dayDir);
      catalog.absorb(merged, existingRel);
      return ImportResult(
        changed ? ImportOutcome.updated : ImportOutcome.duplicate,
        merged,
        existingRel,
      );
    }

    final dayDir = Directory(
        p.join(catalog.root.path, LibraryLayout.dayDirRelative(takenAt)));
    await dayDir.create(recursive: true);

    var fileName = LibraryLayout.fileName(takenAt, name);
    var target = File(p.join(dayDir.path, fileName));
    if (await target.exists()) {
      // 同秒同名但内容不同 —— 用内容 id 后缀区分，可推导、不随导入顺序变化
      fileName = LibraryLayout.fileNameWithSuffix(takenAt, name, id);
      target = File(p.join(dayDir.path, fileName));
      if (await target.exists()) {
        throw StateError('目标已存在且内容不同，拒绝覆盖: ${target.path}');
      }
    }

    await source.copy(target.path);
    // 修改时间设成拍摄时间，Finder 里排序才对（复制会丢 mtime，所以显式设）
    try {
      await target.setLastModified(takenAt);
    } catch (_) {
      // 某些文件系统不支持，不影响正确性
    }

    final sc = await Sidecar.load(dayDir);
    sc.put(fileName, incoming);
    await sc.save(dayDir);

    final rel = p.relative(target.path, from: catalog.root.path);
    catalog.absorb(incoming, rel);
    return ImportResult(ImportOutcome.imported, incoming, rel);
  }
}
