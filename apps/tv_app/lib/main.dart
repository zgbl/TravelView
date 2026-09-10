import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tv_shared/tv_shared.dart';

import 'pages/app_shell.dart';
import 'ui/theme.dart';
import 'state/mobile_image_ops.dart';
import 'state/session.dart';
import 'state/workspace.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 共享层要靠这两句才能在手机上跑起来，**必须在任何界面之前**:
  //   - 沙盒配置目录要问系统要，桌面端那套按平台拼路径的办法在这里行不通
  //   - 图像操作换成走系统相册的实现
  AppSettings.configDir = await getApplicationSupportDirectory();

  // 派生图、打包产物这些中间文件全部落在这个临时目录里。
  // **手机上唯一会被写入的地方** —— 系统相册里的原件一个字节都不动。
  await Workspace.init();

  ImageOps.register(const MobileImageOps());

  final session = await Session.load();
  L10n.set(session.settings.uiLang.isEmpty
      ? L10n.guessFromSystem()
      : session.settings.uiLang);

  runApp(TravelViewApp(session));
}

class TravelViewApp extends StatelessWidget {
  final Session session;
  const TravelViewApp(this.session, {super.key});

  @override
  Widget build(BuildContext context) {
    // 和桌面端一样，整棵树挂在语言这个 ValueNotifier 上
    return ValueListenableBuilder<String>(
      valueListenable: L10n.lang,
      builder: (context, _, __) => MaterialApp(
        title: 'TravelView',
        debugShowCheckedModeBanner: false,
        theme: TV.theme(Brightness.light),
        darkTheme: TV.theme(Brightness.dark),
        home: AppShell(session),
      ),
    );
  }

}
