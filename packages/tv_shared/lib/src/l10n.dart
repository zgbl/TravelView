import 'dart:io';

import 'package:flutter/foundation.dart';

import 'l10n_en.dart';

/// 界面语言。
///
/// **用中文原文当 key，不发明 key 名。**
/// 这是给一个已经写满中文字面量的项目做双语最省事、也最不容易出错的办法:
///   - 不用为四百多条文案想名字，也不会出现 `label_23` 这种没人看得懂的 key
///   - 漏翻的地方**自动回落成中文**，不会变成 `MISSING_KEY_42` 显示给用户
///   - 中文那一份永远不用维护，改中文原文时顺手改 key 即可
///
/// 代价是改中文原文会让对应的英文失效 —— 用下面的扫描脚本能立刻查出来:
///   dart run tool/i18n_scan.dart
class L10n {
  L10n._();

  static final ValueNotifier<String> lang = ValueNotifier<String>('zh');

  static bool get isEn => lang.value == 'en';

  /// 第一次启动按系统语言猜。**之后完全由用户说了算** ——
  /// 很多人系统是英文但更愿意用中文界面，反过来也一样。
  static String guessFromSystem() {
    final l = Platform.localeName.toLowerCase();   // 如 zh_CN.UTF-8
    return l.startsWith('zh') ? 'zh' : 'en';
  }

  static void set(String v) {
    lang.value = (v == 'en') ? 'en' : 'zh';
  }
}

/// 翻译一条文案。**参数就是中文原文** —— 找不到译文就原样返回中文。
///
///     Text(tr('发布'))
String tr(String zh) {
  if (!L10n.isEn) return zh;
  return kEn[zh] ?? zh;
}

/// 带占位符的文案。占位符写成 {0} {1}，按顺序替换。
///
///     trf('已选 {0} / {1} 张', [picked, total])
///
/// **不要用 Dart 的字符串插值再去查表** —— 插值在运行时就拼好了，
/// 查表拿到的是"已选 3 / 12 张"这种具体值，永远命中不了。
String trf(String zh, List<Object?> args) {
  var s = tr(zh);
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}
