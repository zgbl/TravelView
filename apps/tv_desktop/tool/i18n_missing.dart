// 查出**已经包了 tr() 但 l10n_en.dart 里没有译文**的文案 ——
// 这类在英文界面上会静悄悄地显示中文，比没接入更难发现。
//
//   dart run tool/i18n_missing.dart
import 'dart:io';

import '../lib/state/l10n_en.dart';

void main() {
  final cjk = RegExp(r'[一-鿿]');
  final call = RegExp(r"tr f?\(\s*'((?:[^'\\]|\\.)*)'");
  final missing = <String, String>{};

  for (final f in Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    if (f.path.endsWith('l10n_en.dart')) continue;
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      for (final m in call.allMatches(lines[i])) {
        final k = m.group(1)!;
        if (!cjk.hasMatch(k)) continue;
        if (!kEn.containsKey(k)) missing[k] = '${f.path}:${i + 1}';
      }
    }
  }

  if (missing.isEmpty) {
    stdout.writeln('没有漏翻的');
    return;
  }
  stdout.writeln('${missing.length} 条包了 tr() 但没有英文:\n');
  missing.forEach((k, where) {
    stdout.writeln("  '${k.replaceAll("'", r"\'")}': '',   // $where");
  });
  exitCode = 1;
}
