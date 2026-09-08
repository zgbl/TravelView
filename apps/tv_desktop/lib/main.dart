import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'state/l10n.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 默认的错误组件在 release 下是一片灰黑、什么信息都没有。
  // 换成能看清错误、并且明确告诉用户按 Esc 返回的样子。
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF1A1113),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.orangeAccent, size: 40),
              const SizedBox(height: 12),
              Text(tr('这一块出错了（按 Esc 返回）'),
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 10),
              SelectableText(
                details.exceptionAsString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  };

  runApp(const TravelViewApp());
}

class TravelViewApp extends StatelessWidget {
  const TravelViewApp({super.key});

  static const _seed = Color(0xFF2E6F6A);

  @override
  Widget build(BuildContext context) {
    // **整棵树挂在语言这个 ValueNotifier 上。**
    // 切换语言要让每一个 Text 重建 —— 让每个页面自己去监听，
    // 一定会漏掉几个，用户就会看到半中半英的界面
    return ValueListenableBuilder<String>(
      valueListenable: L10n.lang,
      builder: (context, _, __) => MaterialApp(
        title: 'TravelView',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const HomePage(),
      ),
    );
  }

  static ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? scheme.surface
          : const Color(0xFFF7F7F5),
      visualDensity: VisualDensity.compact,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
