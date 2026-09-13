import 'package:flutter/material.dart';
import 'package:tv_core/tv_core.dart';

import 'l10n.dart';

/// 忘记密码。桌面端和手机端共用这一段。
///
/// **App 里只做"发信"，新密码在网页上设。** 在 App 里再实现一套
/// 收验证码、改密码的流程，等于把认证逻辑写两遍 ——
/// 而最松的那一处就决定了整个系统的安全水位。
/// 邮件里那个链接只能用一次、一小时过期，用户点开就能改。
///
/// 输入框里已经填了邮箱就直接用它：走到"忘记密码"这一步的人，
/// 十有八九邮箱是记得的，让他再打一遍没有道理。
class ForgotPassword {
  static Future<void> show(
    BuildContext context, {
    required String siteUrl,
    String email = '',
  }) async {
    final ctl = TextEditingController(text: email.trim());
    var busy = false;
    String? error;
    var sent = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final scheme = Theme.of(ctx).colorScheme;

          Future<void> submit() async {
            final addr = ctl.text.trim();
            // 服务器也会校验；这里拦一下纯粹是为了不让用户白等一个来回
            if (!addr.contains('@') || addr.length < 5) {
              setLocal(() => error = tr('邮箱格式不对'));
              return;
            }
            setLocal(() {
              busy = true;
              error = null;
            });
            try {
              await DesktopLogin(siteUrl)
                  .requestPasswordReset(addr, locale: L10n.isEn ? 'en' : 'zh');
              setLocal(() => sent = true);
            } on LoginException catch (e) {
              setLocal(() => error = e.message);
            } catch (e) {
              setLocal(() => error = '$e');
            } finally {
              setLocal(() => busy = false);
            }
          }

          if (sent) {
            return AlertDialog(
              title: Text(tr('信已经发出去了')),
              content: SizedBox(
                width: 380,
                child: Text(
                  tr('去邮箱点那个链接，就能设置新密码。链接 1 小时内有效，'
                      '只能用一次。\n\n'
                      '没收到就看看垃圾邮件；如果这个邮箱没有注册过，'
                      '是不会收到信的。'),
                  style: const TextStyle(fontSize: 13, height: 1.6),
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(tr('知道了')),
                ),
              ],
            );
          }

          return AlertDialog(
            title: Text(tr('重置密码')),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('填你注册时用的邮箱，我们发一个链接过去，'
                        '在网页上点开就能设新密码。'),
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: ctl,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    onSubmitted: (_) => busy ? null : submit(),
                    decoration: InputDecoration(
                      labelText: tr('邮箱'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!,
                        style: TextStyle(fontSize: 12, color: scheme.error)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                child: Text(tr('取消')),
              ),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(busy ? tr('正在发送...') : tr('发送重置链接')),
              ),
            ],
          );
        },
      ),
    );
    ctl.dispose();
  }
}
