import 'package:flutter/material.dart';

import '../state/library_controller.dart';

/// 界面语言开关，常驻顶栏。
///
/// **不放进设置对话框深处。** 一个看不懂当前界面语言的人，
/// 恰恰最没能力在层层菜单里找到"语言设置"这一项 ——
/// 所以它必须在第一屏就能看见，而且两种语言都用**它自己的写法**标出来
/// （中文 / English），不翻译成对方的语言。
class LangSwitch extends StatefulWidget {
  final LibraryController c;
  const LangSwitch({super.key, required this.c});

  @override
  State<LangSwitch> createState() => _LangSwitchState();
}

class _LangSwitchState extends State<LangSwitch> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final en = widget.c.uiLang == 'en';

    Widget half(String label, bool active, String code) => InkWell(
          onTap: active ? null : () async {
            await widget.c.setUiLang(code);
            if (mounted) setState(() {});
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
        );

    return Tooltip(
      message: 'Language / 语言',
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          half('中文', !en, 'zh'),
          Container(width: 1, height: 14, color: scheme.outlineVariant),
          half('EN', en, 'en'),
        ]),
      ),
    );
  }
}
