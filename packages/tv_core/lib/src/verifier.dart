import 'dart:io';

import 'package:path/path.dart' as p;

import 'catalog.dart';
import 'fingerprint.dart';

class VerifyReport {
  final int checked;
  final List<LibraryIssue> problems;
  const VerifyReport(this.checked, this.problems);
  bool get ok => problems.isEmpty;
}

/// 逐个重算内容哈希，和 id 比对。
/// 没有校验的备份是自我安慰 —— 这是 `tv verify` 的实现。
class Verifier {
  final Catalog catalog;
  Verifier(this.catalog);

  Future<VerifyReport> run({void Function(int done, int total)? onProgress}) async {
    final problems = <LibraryIssue>[];
    final ids = catalog.photos.map((r) => r.id).toList();
    var done = 0;

    for (final id in ids) {
      final rel = catalog.relPathOf(id);
      if (rel == null) {
        problems.add(LibraryIssue('missing', id, '索引里没有路径'));
        continue;
      }
      final f = File(p.join(catalog.root.path, rel));
      if (!await f.exists()) {
        problems.add(LibraryIssue('missing', rel, '文件不存在'));
      } else {
        final actual = await Fingerprint.contentId(f);
        if (actual != id) {
          problems.add(LibraryIssue('mismatch', rel, '内容已改变: $id -> $actual'));
        }
      }
      onProgress?.call(++done, ids.length);
    }
    return VerifyReport(ids.length, problems);
  }
}
