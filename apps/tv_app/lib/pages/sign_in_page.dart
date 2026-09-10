import 'package:flutter/material.dart';
import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

import '../state/account.dart';

/// 登录 / 注册。**同一屏，切一下就行。**
///
/// 用户点「发布」的时候脑子里想的是发布，不是办账号 —— 这一屏是拦路的，
/// 越快过去越好。所以：
///
///   - 注册**不跳浏览器**。跳出去要重新输一遍邮箱密码、回来还得手动切回 App，
///     一半的人在这一步就走了
///   - 注册成功**直接就是登录状态**，不让人把刚打完的邮箱密码再打一遍
///   - 密码规则跟着服务器走，客户端不复制一份 —— 两边迟早会不一致
///
/// 找回密码还是留在网页上：那条路要收邮件，本来就得离开 App。
class SignInPage extends StatefulWidget {
  final Account account;
  const SignInPage(this.account, {super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _signUp = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      if (_signUp) {
        await widget.account.signUp(_email.text.trim(), _pass.text);
      } else {
        await widget.account.signIn(_email.text.trim(), _pass.text);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on LoginException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_signUp ? tr('注册账号') : tr('登录'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        children: [
          Text(
            tr('发布需要一个账号。只有你选中的照片会被缩小后上传，'
                '原件一直留在你手机里。'),
            style: TextStyle(
                color: Theme.of(context).colorScheme.outline, fontSize: 13),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: tr('邮箱'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pass,
            obscureText: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: tr('密码'),
              helperText: _signUp ? tr('至少 8 位') : null,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_signUp ? tr('注册并登录') : tr('登录')),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _signUp = !_signUp;
                      _error = null;
                    }),
            child: Text(_signUp
                ? tr('已经有账号了，去登录')
                : tr('还没有账号？注册一个')),
          ),
        ],
      ),
    );
  }
}
