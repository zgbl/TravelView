import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tv_core/tv_core.dart';

const _usage = '''
tv —— TravelView 照片库命令行

用法:
  tv init     <库目录>
  tv import   <库目录> <源目录>      从源目录导入（只读源文件，永不删除）
  tv rebuild  <库目录>               删掉索引，从文件树+sidecar 完整重建
  tv verify   <库目录>               逐个重算内容哈希校验
  tv stats    <库目录>               统计与各维度分面
''';

Future<void> main(List<String> args) async {
  exit(await _run(args));
}

Future<int> _run(List<String> args) async {
  if (args.isEmpty) {
    stdout.write(_usage);
    return 64;
  }
  final cmd = args[0];
  if (args.length < 2) {
    stderr.writeln('缺少库目录参数\n$_usage');
    return 64;
  }
  final root = Directory(args[1]);

  switch (cmd) {
    case 'init':
      return _init(root);
    case 'import':
      if (args.length < 3) {
        stderr.writeln('用法: tv import <库目录> <源目录>');
        return 64;
      }
      return _import(root, Directory(args[2]));
    case 'rebuild':
      return _rebuild(root);
    case 'verify':
      return _verify(root);
    case 'stats':
      return _stats(root);
    default:
      stderr.writeln('未知命令: $cmd\n$_usage');
      return 64;
  }
}

Future<int> _init(Directory root) async {
  await Directory(p.join(root.path, LibraryLayout.photosDir))
      .create(recursive: true);
  await Directory(p.join(root.path, LibraryLayout.catalogDir))
      .create(recursive: true);
  final readme = File(p.join(root.path, LibraryLayout.readmeName));
  if (!await readme.exists()) {
    await readme.writeAsString(_readmeText);
  }
  stdout.writeln('已初始化照片库: ${root.path}');
  return 0;
}

Future<int> _import(Directory root, Directory src) async {
  if (!await src.exists()) {
    stderr.writeln('源目录不存在: ${src.path}');
    return 66;
  }
  await _init(root);
  final catalog = Catalog(root);
  await catalog.rebuild();
  final importer = Importer(catalog);

  var imported = 0, dup = 0, updated = 0;
  await for (final e in src.list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    if (p.basename(e.path).startsWith('.')) continue;
    final stat = await e.stat();
    final r = await importer.importFile(e, takenAt: stat.modified);
    if (r.outcome == ImportOutcome.imported) {
      imported++;
    } else if (r.outcome == ImportOutcome.updated) {
      updated++;
    } else {
      dup++;
    }
  }
  await catalog.writeJsonl();
  stdout.writeln('导入 $imported 张，重复跳过 $dup 张，元数据更新 $updated 张');
  return 0;
}

Future<int> _rebuild(Directory root) async {
  final catalog = Catalog(root);
  final r = await catalog.rebuild();
  await catalog.writeJsonl();
  stdout.writeln('重建完成: ${r.photoCount} 张照片，${r.dayDirCount} 个日期目录');
  for (final issue in r.issues) {
    stdout.writeln('  $issue');
  }
  return r.issues.any((i) => i.kind == 'missing') ? 1 : 0;
}

Future<int> _verify(Directory root) async {
  final catalog = Catalog(root);
  await catalog.rebuild();
  final report = await Verifier(catalog).run();
  if (report.ok) {
    stdout.writeln('校验通过: ${report.checked} 张照片全部完好');
    return 0;
  }
  stdout.writeln('校验发现 ${report.problems.length} 个问题:');
  for (final i in report.problems) {
    stdout.writeln('  $i');
  }
  return 1;
}

Future<int> _stats(Directory root) async {
  final catalog = Catalog(root);
  await catalog.rebuild();
  final total = catalog.length;
  final withGps = catalog.query(hasLocation: true).length;
  stdout.writeln('照片总数: $total');
  stdout.writeln('含 GPS  : $withGps');
  for (final kind in ['trip', 'place', 'person', 'album']) {
    final f = catalog.facet(kind);
    if (f.isEmpty) continue;
    stdout.writeln('$kind:');
    final entries = f.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in entries.take(10)) {
      stdout.writeln('  ${e.key}: ${e.value}');
    }
  }
  return 0;
}

const _readmeText = '''
# 这个文件夹是什么

这是一个 TravelView 照片库。它的设计目标是：**十年后你不需要任何软件也能用。**

- `photos/` 是你的照片原件，按拍摄日期组织，都是普通文件，直接双击就能打开。
- 每个日期目录里的 `.tvmeta.json` 记录了这些照片的时间、位置、所属旅行等信息。
  这是元数据的**真相**，它跟着照片走 —— 你把某个文件夹拷到别处，信息一起走。
- `catalog/` 只是为了查得快而生成的索引，**可以随时整个删掉**，
  用 `tv rebuild` 就能从上面两样东西完整重建。
- `views/` 是按旅行/地点/人物等维度生成的视图，同样可以删掉重建，
  里面不含照片的第二份字节。

你可以在访达里随意改名、移动、重新分类这些照片。
下次扫描时，程序靠文件内容的哈希重新认出它们，不会重复导入，也不会丢元数据。
''';
