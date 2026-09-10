import 'package:flutter/material.dart';

/// TravelView 手机端的视觉规范。
///
/// **一处定义，全局引用。** 之前每个页面各写各的圆角和间距，
/// 结果同一个 App 里出现了 4px / 6px / 12px / 16px 四种圆角 ——
/// 用户说不出哪里不对，但会觉得"这东西做得糙"。
///
/// 色彩：旅行蓝作主色（照片是主角，界面不能抢；蓝色是天空和海，
/// 和旅行照片放在一起最不打架），配浅灰底 #F7F9FC —— 纯白底会让
/// 照片边缘"发飘"，一点点灰能把照片托住。
class TV {
  TV._();

  // ── 色 ──
  static const seed = Color(0xFF1F6FEB);      // 旅行蓝
  static const ink = Color(0xFF0E1726);       // 深色文字
  static const canvas = Color(0xFFF7F9FC);    // 浅灰底
  static const canvasDark = Color(0xFF0F1418);

  // ── 圆角 ──
  static const rCard = 16.0;      // 卡片
  static const rControl = 12.0;   // 按钮、输入框
  static const rChip = 999.0;     // 胶囊

  // ── 间距 ──
  static const gap = 12.0;
  static const pad = 16.0;

  /// 精细浅阴影。**只有一档。**
  /// 多档阴影需要一套完整的层级语言才不乱，我们的界面没那么深。
  static List<BoxShadow> shadow(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.34 : 0.07),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ];
  }

  /// 照片上压文字时用的渐变蒙版。
  ///
  /// 从中间开始才有渐变 —— 从顶部就压黑会把照片糟蹋掉，
  /// 而封面照片本身才是用户想看的东西。
  static const scrim = LinearGradient(
    begin: Alignment.center,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xCC000000)],
  );

  static ThemeData theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final dark = brightness == Brightness.dark;

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: dark ? canvasDark : canvas,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? canvasDark : canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: dark ? Colors.white : ink,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF171D24) : Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rCard),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF141A21) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 66,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 11.5,
              fontWeight:
                  s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: s.contains(WidgetState.selected)
                  ? scheme.primary
                  : scheme.outline,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              size: 24,
              color: s.contains(WidgetState.selected)
                  ? scheme.primary
                  : scheme.outline,
            )),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF171D24) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rControl),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rControl),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rControl),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rControl),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rChip),
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: pad, vertical: 2),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
