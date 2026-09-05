import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tv_core/tv_core.dart';

import 'helpers.dart';

void main() {
  late Directory lib;
  late Directory src;

  setUp(() {
    lib = makeTempLib();
    src = makeTempLib();
  });

  tearDown(() {
    if (lib.existsSync()) lib.deleteSync(recursive: true);
    if (src.existsSync()) src.deleteSync(recursive: true);
  });

  Future<Catalog> freshCatalog() async {
    final c = Catalog(lib);
    await c.rebuild();
    return c;
  }

  test('导入: 落到按时间的目录，文件名可排序', () async {
    final c = await freshCatalog();
    final f = makeFakePhoto(src, 'IMG_1234.HEIC', seed: 1);
    final r = await Importer(c).importFile(f, takenAt: at(2025, 9, 12, 14, 30, 22));

    expect(r.outcome, ImportOutcome.imported);
    expect(r.relPath,
        'photos/2025/2025-09-12/2025-09-12 14-30-22 IMG_1234.HEIC',
        reason: '索引里的路径一律用 / 分隔，Mac 和 Windows 读同一块移动硬盘才不会打架');
    expect(File(p.joinAll([lib.path, ...p.posix.split(r.relPath)])).existsSync(),
        isTrue);
    // 原则: 只读源文件，永不删除
    expect(f.existsSync(), isTrue);
  });

  test('原则 2: 同一内容重复导入不产生第二份字节', () async {
    final c = await freshCatalog();
    final a = makeFakePhoto(src, 'a.jpg', seed: 5);
    final b = makeFakePhoto(src, 'b_copy.jpg', seed: 5); // 内容相同、名字不同

    final imp = Importer(c);
    final r1 = await imp.importFile(a, takenAt: at(2025, 3, 1));
    final r2 = await imp.importFile(b, takenAt: at(2025, 3, 1));

    expect(r1.outcome, ImportOutcome.imported);
    expect(r2.outcome, anyOf(ImportOutcome.duplicate, ImportOutcome.updated));
    expect(r2.relPath, r1.relPath);
    expect(c.length, 1);

    final files = Directory(p.join(lib.path, 'photos', '2025', '2025-03-01'))
        .listSync()
        .whereType<File>()
        .where((f) => !p.basename(f.path).startsWith('.'))
        .toList();
    expect(files.length, 1, reason: '同一张照片只能有一份字节');
  });

  test('重复导入时补上的元数据会被合并，不丢信息', () async {
    final c = await freshCatalog();
    final a = makeFakePhoto(src, 'a.jpg', seed: 6);
    final imp = Importer(c);

    await imp.importFile(a, takenAt: at(2025, 4, 2));
    final r = await imp.importFile(a,
        takenAt: at(2025, 4, 2), lat: 35.0, lon: 135.0, tags: [const Tag('trip', 'kyoto')]);

    expect(r.outcome, ImportOutcome.updated);
    expect(r.record.lat, 35.0);
    expect(r.record.tags, contains(const Tag('trip', 'kyoto')));
  });

  test('同一秒同名但内容不同 -> 用内容 id 后缀区分，不覆盖', () async {
    final c = await freshCatalog();
    final t = at(2025, 5, 5, 10, 0, 0);
    final a = makeFakePhoto(src, 'IMG_1.JPG', seed: 11);
    final b = makeFakePhoto(Directory(p.join(src.path, 'sub')), 'IMG_1.JPG', seed: 22);

    final imp = Importer(c);
    final r1 = await imp.importFile(a, takenAt: t);
    final r2 = await imp.importFile(b, takenAt: t);

    expect(r2.outcome, ImportOutcome.imported);
    expect(r1.relPath, isNot(r2.relPath));
    expect(c.length, 2);
  });

  test('原则 3: 删掉 catalog 能从文件树+sidecar 完整重建', () async {
    final c = await freshCatalog();
    final imp = Importer(c);
    for (var i = 0; i < 5; i++) {
      final f = makeFakePhoto(src, 'p$i.jpg', seed: 100 + i);
      await imp.importFile(f,
          takenAt: at(2025, 9, 10 + i, 9, 0, i),
          lat: 34.0 + i,
          lon: 135.0 + i,
          tags: [const Tag('trip', 'kyoto-2025')]);
    }
    await c.writeJsonl();

    // 把派生的索引整个删掉
    Directory(p.join(lib.path, LibraryLayout.catalogDir)).deleteSync(recursive: true);

    final rebuilt = Catalog(lib);
    final res = await rebuilt.rebuild();

    expect(res.photoCount, 5);
    expect(rebuilt.query(tagKind: 'trip', tagValue: 'kyoto-2025').length, 5);
    expect(rebuilt.facet('trip')['kyoto-2025'], 5);
    expect(res.issues.where((i) => i.kind == 'missing'), isEmpty);
    expect(rebuilt.photos.every((r) => r.hasLocation), isTrue);
  });

  test('原则 4: 用户在访达里改名/移动，靠内容哈希自愈认领', () async {
    final c = await freshCatalog();
    final f = makeFakePhoto(src, 'orig.jpg', seed: 42);
    final r = await Importer(c).importFile(f, takenAt: at(2025, 6, 1, 8, 0, 0));

    // 模拟用户手动改名（sidecar 里还是老名字）
    final onDisk = File(p.joinAll([lib.path, ...p.posix.split(r.relPath)]));
    final renamed = File(p.join(onDisk.parent.path, '我改的名字.jpg'));
    onDisk.renameSync(renamed.path);

    final rebuilt = Catalog(lib);
    final res = await rebuilt.rebuild();

    // 不能当成新照片重复导入，要认出这是已知的那一张
    final adopted = res.issues.where((i) => i.kind == 'adopted').toList();
    expect(adopted.length, 1, reason: '应认领改名后的文件');
    expect(adopted.first.path, contains('我改的名字'));
  });

  test('verify: 内容被篡改能被查出来', () async {
    final c = await freshCatalog();
    final f = makeFakePhoto(src, 'x.jpg', seed: 9);
    final r = await Importer(c).importFile(f, takenAt: at(2025, 7, 7));

    expect((await Verifier(c).run()).ok, isTrue);

    File(p.joinAll([lib.path, ...p.posix.split(r.relPath)])).writeAsBytesSync([1, 2, 3]);
    final report = await Verifier(c).run();
    expect(report.ok, isFalse);
    expect(report.problems.single.kind, 'mismatch');
  });

  test('verify: 文件被删能被查出来', () async {
    final c = await freshCatalog();
    final f = makeFakePhoto(src, 'y.jpg', seed: 10);
    final r = await Importer(c).importFile(f, takenAt: at(2025, 8, 8));
    File(p.joinAll([lib.path, ...p.posix.split(r.relPath)])).deleteSync();

    final report = await Verifier(c).run();
    expect(report.problems.single.kind, 'missing');
  });

  test('sidecar 是真相: 它单独就够重建元数据', () async {
    final c = await freshCatalog();
    final f = makeFakePhoto(src, 'z.jpg', seed: 33);
    await Importer(c).importFile(f,
        takenAt: at(2025, 10, 1, 7, 30, 0),
        lat: 1.5,
        lon: 2.5,
        device: 'iPhone 12 Pro Max',
        tags: [const Tag('place', '京都'), const Tag('person', 'mom')]);

    final dayDir = Directory(p.join(lib.path, 'photos', '2025', '2025-10-01'));
    final sc = await Sidecar.load(dayDir);
    final rec = sc.photos.values.single;

    expect(rec.lat, 1.5);
    expect(rec.device, 'iPhone 12 Pro Max');
    expect(rec.tags.map((t) => t.toString()),
        containsAll(['place:京都', 'person:mom']));
  });

  test('多维度共存: 一张照片同时属于旅行和人物，字节仍只有一份', () async {
    final c = await freshCatalog();
    final f = makeFakePhoto(src, 'multi.jpg', seed: 77);
    await Importer(c).importFile(f,
        takenAt: at(2025, 9, 12),
        tags: [
          const Tag('trip', 'kyoto-2025'),
          const Tag('person', 'mom'),
          const Tag('album', '收藏'),
        ]);

    expect(c.query(tagKind: 'trip', tagValue: 'kyoto-2025').length, 1);
    expect(c.query(tagKind: 'person', tagValue: 'mom').length, 1);
    expect(c.query(tagKind: 'album', tagValue: '收藏').length, 1);
    expect(c.length, 1);
  });

  test('setTag: 选取与取消选取都要落到 sidecar', () async {
    final c = await freshCatalog();
    final f = makeFakePhoto(src, 'pick.jpg', seed: 88);
    final r = await Importer(c).importFile(f, takenAt: at(2025, 9, 20));
    const pick = Tag('pick', '精选');

    await c.setTag(r.record.id, pick, on: true);
    expect(c.byId(r.record.id)!.tags, contains(pick));

    // 重建后仍在 —— 说明真的写进了 sidecar，不只是内存
    var reloaded = Catalog(lib);
    await reloaded.rebuild();
    expect(reloaded.byId(r.record.id)!.tags, contains(pick));

    // 取消选取必须真的删掉，不能被 merge 又并回来
    await c.setTag(r.record.id, pick, on: false);
    reloaded = Catalog(lib);
    await reloaded.rebuild();
    expect(reloaded.byId(r.record.id)!.tags, isNot(contains(pick)),
        reason: '取消选取要能真的去掉 tag');
  });

  test('setTag: 取消选取不影响其它 tag', () async {
    final c = await freshCatalog();
    final f = makeFakePhoto(src, 'multi2.jpg', seed: 89);
    final r = await Importer(c).importFile(f,
        takenAt: at(2025, 9, 21), tags: [const Tag('trip', 'usa-2025')]);
    const pick = Tag('pick', '精选');
    await c.setTag(r.record.id, pick, on: true);
    await c.setTag(r.record.id, pick, on: false);
    expect(c.byId(r.record.id)!.tags, contains(const Tag('trip', 'usa-2025')));
  });

  test('refreshAfterEdit: 内容变了换新 id，但标签和拍摄时间都保住', () async {
    final c = await freshCatalog();
    final f = makeFakePhoto(src, 'rot.jpg', seed: 91);
    final r = await Importer(c).importFile(f,
        takenAt: at(2025, 9, 22, 10, 30, 0),
        lat: 36.1,
        lon: -112.1,
        tags: [const Tag('trip', 'usa-2025'), const Tag('pick', '精选')]);
    final oldId = r.record.id;

    // 模拟就地修改文件内容（旋转会改 EXIF 方向标记）
    final onDisk = File(p.joinAll([lib.path, ...p.posix.split(r.relPath)]));
    onDisk.writeAsBytesSync([...onDisk.readAsBytesSync(), 1, 2, 3]);

    final updated = await c.refreshAfterEdit(oldId);
    expect(updated, isNotNull);
    expect(updated!.id, isNot(oldId), reason: '内容变了 id 必须跟着变');
    expect(updated.takenAt, at(2025, 9, 22, 10, 30, 0));
    expect(updated.lat, 36.1);
    expect(updated.tags, containsAll(
        [const Tag('trip', 'usa-2025'), const Tag('pick', '精选')]));
    expect(c.byId(oldId), isNull, reason: '旧 id 不该还在索引里');

    // 重建后依然一致 —— 说明真的写进了 sidecar
    final reloaded = Catalog(lib);
    await reloaded.rebuild();
    expect(reloaded.byId(updated.id), isNotNull);
    expect(reloaded.byId(updated.id)!.tags, contains(const Tag('pick', '精选')));
  });

  test('JSONL 镜像可读且每行一条', () async {
    final c = await freshCatalog();
    final imp = Importer(c);
    for (var i = 0; i < 3; i++) {
      await imp.importFile(makeFakePhoto(src, 'j$i.jpg', seed: 200 + i),
          takenAt: at(2025, 11, 1 + i));
    }
    await c.writeJsonl();
    final lines = c.jsonlFile.readAsLinesSync().where((l) => l.trim().isNotEmpty);
    expect(lines.length, 3);
    expect(lines.first, contains('"path"'));
  });
}
