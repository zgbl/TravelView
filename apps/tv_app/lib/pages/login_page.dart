import 'package:flutter/material.dart';
import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

import '../state/session.dart';

/// 开屏就是这一页。登录和注册在同一屏，切一下就行。
///
/// 只有邮箱和密码两个框。注册**不跳浏览器**、注册完**直接就是登录状态** ——
/// 跳出去要重输一遍、回来还得手动切回 App，一半的人在这一步就走了。
class LoginPage extends StatefulWidget {
  final Session session;
  const LoginPage(this.session, {super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_signUp) {
        await widget.session.account
            .signUp(_email.text.trim(), _pass.text);
      } else {
        await widget.session.account
            .signIn(_email.text.trim(), _pass.text);
      }
      widget.session.refresh();
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(26, 60, 26, 26),
          children: [
            Icon(Icons.travel_explore, size: 46, color: scheme.primary),
            const SizedBox(height: 18),
            const Text('TravelView',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              tr('把手机里的照片变成一篇可以分享的旅行回顾。'),
              style: TextStyle(fontSize: 14, color: scheme.outline),
            ),
            const SizedBox(height: 36),
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
                  style: TextStyle(color: scheme.error, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_signUp ? tr('注册并登录') : tr('登录')),
              ),
            ),
            const SizedBox(height: 4),
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
            const SizedBox(height: 20),
            Text(
              tr('只有你选中的照片会被缩小后上传，原件一直留在你手机里。'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
