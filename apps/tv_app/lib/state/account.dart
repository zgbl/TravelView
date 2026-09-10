import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

/// 手机端的账号状态。
///
/// 登录走的是**桌面端那个同样的接口** —— 一个账号在哪台设备上登录都一样，
/// 没有理由为手机再造一套。拿到的 token 存在 `AppSettings` 里，
/// 和桌面端同一个字段名。
class Account {
  Account(this.settings);

  final AppSettings settings;

  bool get signedIn => settings.publishToken.trim().isNotEmpty;

  PublishConfig get config => PublishConfig(
        siteUrl: settings.siteUrl,
        token: settings.publishToken,
      );

  Future<void> signIn(String email, String password) async {
    final token = await DesktopLogin(settings.siteUrl)
        .signIn(email, password, label: 'Phone');
    settings.publishToken = token;
    await settings.save();
  }

  /// 注册完直接就是登录状态 —— 见 `DesktopLogin.signUp`。
  Future<void> signUp(String email, String password, {String? name}) async {
    final token = await DesktopLogin(settings.siteUrl)
        .signUp(email, password, name: name, label: 'Phone');
    settings.publishToken = token;
    await settings.save();
  }

  Future<void> signOut() async {
    settings.publishToken = '';
    await settings.save();
  }
}
