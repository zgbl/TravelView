// 查出还没接入双语的中文文案。
//
//   dart run tool/i18n_scan.dart          列出还没包 tr() 的中文字面量
//   dart run tool/i18n_scan.dart --todo   只输出待翻译的 key（可直接贴进 l10n_en.dart）
//
// 判定很朴素: 一条含中文的字符串字面量，**前面紧挨着 tr( 或 trf(** 就算已接入。
// 不做完整的 Dart 解析 —— 那需要 analyzer 包，而这个脚本要的只是一份清单。
//
// **注释里的中文不算**（源码注释本来就该是中文），
// lib/export/web_template.dart 整个跳过 —— 那是导出网页的内容，
// 它的双语由网页自己的 locale 决定，和桌面界面语言无关。
import 'dart:io';

/// 要扫的代码根目录。文案现在分散在三处：桌面界面、手机界面、以及两端共用的
/// `tv_shared`。**漏掉任何一个，英文界面上就会冒出中文。**
const _roots = [
  'lib',
  '../tv_app/lib',
  '../../packages/tv_shared/lib',
];

Iterable<File> _dartFiles() sync* {
  for (final r in _roots) {
    final d = Directory(r);
    if (!d.existsSync()) continue;
    yield* d
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
  }
}

void main(List<String> args) {
  final todoOnly = args.contains('--todo');
  final cjk = RegExp(r'[一-鿿]');
  final lit = RegExp(r"'((?:[^'\\\n]|\\.)*)'");

  final missing = <String, List<String>>{};   // 文案 -> 出现的位置
  var done = 0;

  for (final f in _dartFiles()) {
    if (f.path.endsWith('web_template.dart')) continue;
    if (f.path.endsWith('l10n_en.dart')) continue;

    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final t = line.trimLeft();
      if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) continue;

      for (final m in lit.allMatches(line)) {
        final v = m.group(1)!;
        if (!cjk.hasMatch(v)) continue;
        // 往前看一小段，判断是不是已经被 tr( / trf( 包起来
        final before = line.substring(0, m.start);
        if (RegExp(r'tr f?\(\s*$').hasMatch(before) ||
            before.endsWith('tr(') || before.endsWith('trf(')) {
          done++;
          continue;
        }
        missing.putIfAbsent(v, () => []).add('${f.path}:${i + 1}');
      }
    }
  }

  if (todoOnly) {
    // 直接可以贴进 l10n_en.dart 的骨架
    final keys = missing.keys.toList()..sort();
    for (final k in keys) {
      stdout.writeln("  '${k.replaceAll("'", r"\'")}': '',");
    }
    return;
  }

  final total = done + missing.values.fold<int>(0, (a, b) => a + b.length);
  stdout.writeln('已接入 tr(): $done / $total');
  stdout.writeln('还没接入: ${missing.length} 条不同的文案\n');
  final keys = missing.keys.toList()
    ..sort((a, b) => missing[b]!.length.compareTo(missing[a]!.length));
  for (final k in keys) {
    stdout.writeln('${missing[k]!.length}×  $k');
    stdout.writeln('      ${missing[k]!.take(3).join('  ')}');
  }
  if (missing.isNotEmpty) exitCode = 1;   // 好接进 CI
}
