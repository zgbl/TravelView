import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tv_shared/tv_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/theme.dart';

/// 分享面板：二维码 + 链接 + 三个动作。
///
/// **二维码是给面对面的人用的。** 一桌人吃饭，把手机举起来让人扫，
/// 比"你微信多少我发给你"快得多 —— 而这正是旅行回顾最常被分享的场合。
Future<void> showShareSheet(BuildContext context, String url,
    {String? title}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null) ...[
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
              ],
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(TV.rCard),
                  boxShadow: TV.shadow(ctx),
                ),
                child: QrImageView(
                  data: url,
                  size: 176,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: TV.ink,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: TV.ink,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(url,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
              const SizedBox(height: 18),
              Row(
                children: [
                  _Action(
                    icon: Icons.ios_share,
                    label: tr('分享'),
                    // 只发裸链接：微信只在整条消息就是一个 URL 时
                    // 才去抓 Open Graph 生成卡片
                    onTap: () => Share.share(url),
                  ),
                  _Action(
                    icon: Icons.link,
                    label: tr('复制'),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(tr('链接已复制'))),
                        );
                      }
                    },
                  ),
                  _Action(
                    icon: Icons.open_in_new,
                    label: tr('打开'),
                    onTap: () => launchUrl(Uri.parse(url),
                        mode: LaunchMode.externalApplication),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Action(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TV.rControl),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: scheme.primary, size: 21),
              ),
              const SizedBox(height: 7),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
