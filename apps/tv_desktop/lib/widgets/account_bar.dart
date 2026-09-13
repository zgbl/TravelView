import 'dart:io';

import 'package:flutter/material.dart';

import '../pages/stories_page.dart';
import '../state/library_controller.dart';
import 'package:tv_shared/tv_shared.dart';

/// 账号状态，常驻主界面顶栏。
///
/// **登录不该埋在发布对话框里。** 用户挑完照片、点了发布，才发现要先处理账号，
/// 这是最糟的打断时机。放在顶栏，他任何时候都能顺手登录，
/// 发布时就只剩发布这一件事。
class AccountBar extends StatefulWidget {
  final LibraryController c;
  const AccountBar({super.key, required this.c});

  @override
  State<AccountBar> createState() => _AccountBarState();
}

class _AccountBarState extends State<AccountBar> {
  @override
  void initState() {
    super.initState();
    widget.c.addListener(_tick);
    // 名字是 ProfileStore 异步取回来的，它自己会通知一次
    widget.c.profile.addListener(_tick);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.c.removeListener(_tick);
    widget.c.profile.removeListener(_tick);
    super.dispose();
  }

  Future<void> _open(String url) async {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    }
  }

  String get _base =>
      widget.c.settings.siteUrl.trim().replaceAll(RegExp(r'/+$'), '');

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final scheme = Theme.of(context).colorScheme;

    if (!c.isLinked) {
      return TextButton.icon(
        onPressed: () => LoginDialog.show(context, c),
        icon: const Icon(Icons.login, size: 15),
        label: Text(tr('登录'), style: const TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: Size.zero),
      );
    }

    final me = c.profile.profile;
    // 名字还在路上（或这次没问到）时退回"已登录" —— 顶栏不能空着或跳动
    final label = me?.displayName ?? tr('已登录');

    return PopupMenuButton<String>(
      tooltip: me?.email ?? tr('账号'),
      onSelected: (v) {
        if (v == 'account') _open('$_base/account');
        // **不跳浏览器。** 自己发的东西要能在 App 里看
        if (v == 'stories') StoriesPage.show(context, c.publishConfig);
        if (v == 'logout') c.logout();
      },
      itemBuilder: (_) => [
        // 谁在登录状态，菜单第一行就说清楚：名字 + 邮箱。
        // 同一台电脑登过几个账号的人，靠这一行分辨
        if (me != null)
          PopupMenuItem(
            enabled: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(me.displayName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(me.email,
                    style: TextStyle(fontSize: 11, color: scheme.outline)),
              ],
            ),
          ),
        if (me != null) const PopupMenuDivider(),
        PopupMenuItem(value: 'account', child: Text(tr('账户页'))),
        PopupMenuItem(value: 'stories', child: Text(tr('我发布的故事'))),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'logout', child: Text(tr('退出登录'))),
      ],
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(
          radius: 9,
          backgroundColor: scheme.primary,
          child: Text(
            me?.initial ?? '?',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: scheme.onPrimary),
          ),
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12)),
        ),
        const Icon(Icons.arrow_drop_down, size: 16),
      ]),
    );
  }
}

/// 登录：邮箱 + 密码。就这一件事，没有第二步。
class LoginDialog extends StatefulWidget {
  final LibraryController c;
  const LoginDialog({super.key, required this.c});

  static Future<void> show(BuildContext context, LibraryController c) =>
      showDialog(context: context, builder: (_) => LoginDialog(c: c));

  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  String get _base =>
      widget.c.settings.siteUrl.trim().replaceAll(RegExp(r'/+$'), '');

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    }
  }

  Future<void> _submit() async {
    final ok = await widget.c.login(_email.text, _password.text);
    if (!mounted) return;
    if (ok) Navigator.pop(context);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final scheme = Theme.of(context).colorScheme;
    final canSubmit = _email.text.trim().isNotEmpty &&
        _password.text.isNotEmpty &&
        !c.loggingIn;

    return AlertDialog(
      title: Text(tr('登录')),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr('邮箱'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => canSubmit ? _submit() : null,
              decoration: InputDecoration(
                labelText: tr('密码'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Text(tr('密码不会保存在这台电脑上。登录后可以在网站账户页随时吊销这台设备。'),
                style: TextStyle(fontSize: 11, color: scheme.outline)),
            if (c.loginError != null) ...[
              const SizedBox(height: 10),
              Text(c.loginError!,
                  style: TextStyle(fontSize: 12, color: scheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _open('$_base/signup'),
          child: Text(tr('还没有账号？免费注册'),
              style: const TextStyle(fontSize: 12)),
        ),
        // 密码想不起来是**在这一刻**发生的事，不能让人退出去自己找网页
        TextButton(
          onPressed: c.loggingIn
              ? null
              : () => ForgotPassword.show(context,
                  siteUrl: c.settings.siteUrl, email: _email.text),
          child: Text(tr('忘记密码？'), style: const TextStyle(fontSize: 12)),
        ),
        TextButton(
          onPressed: c.loggingIn ? null : () => Navigator.pop(context),
          child: Text(tr('取消')),
        ),
        FilledButton(
          onPressed: canSubmit ? _submit : null,
          child: Text(c.loggingIn ? tr('正在登录...') : tr('登录')),
        ),
      ],
    );
  }
}
