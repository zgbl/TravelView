import 'package:flutter/foundation.dart';
import 'package:tv_shared/tv_shared.dart';

import 'account.dart';

/// 整个 App 的会话状态：设置 + 账号。
///
/// **必须先登录才能用。** 这不是为了拦人，是因为这个 App 的每一件事
/// 最后都要落到"发出去"上 —— 挑了半天照片、写了一堆字，到最后一步
/// 才被要求注册，那些工夫可能就白费了（换个账号、注册失败、退出去查邮箱
/// 回来状态没了）。把账号放在最前面，后面每一步都是确定的。
class Session extends ChangeNotifier {
  Session._(this.settings) : account = Account(settings);

  final AppSettings settings;
  Account account;

  static Future<Session> load() async {
    final s = await AppSettings.load();
    return Session._(s);
  }

  bool get signedIn => account.signedIn;

  /// 登录 / 注册成功后调，让 App 从登录页切到主界面。
  void refresh() => notifyListeners();

  Future<void> signOut() async {
    await account.signOut();
    notifyListeners();
  }
}
