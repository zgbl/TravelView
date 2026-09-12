import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tv_shared/tv_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/theme.dart';

/// 分享面板。
///
/// **顺序就是使用频率：系统分享面板在最上面，二维码在下面。**
///
/// 二维码有它的场合 —— 一桌人吃饭，把手机举起来让人扫，比"你微信多少
/// 我发给你"快得多。但那是**面对面**的场合，而绝大多数分享是隔着网络的：
/// 发给不在场的朋友、发到群里、发朋友圈。那些场合里二维码毫无用处，
/// 因为**用户只有一台手机，没法用自己的手机扫自己屏幕上的码**。
///
/// 所以最常用的那个动作必须是一颗全宽的主按钮，不能和"复制""打开"
/// 挤成三个一样大的小图标 —— 它们不是同一个量级的动作。
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
              // ── 主动作：交给系统分享面板 ──
              // 微信、微博、短信、邮件全在里面，一次点击到位
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => Share.share(url),
                  icon: const Icon(Icons.ios_share),
                  label: Text(tr('分享给朋友')),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: url));
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(tr('链接已复制'))),
                          );
                        }
                      },
                      icon: const Icon(Icons.link, size: 18),
                      label: Text(tr('复制')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri.parse(url),
                          mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(tr('打开')),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),
              // ── 次要：当面扫码 ──
              Text(tr('当面给对方扫'),
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(TV.rCard),
                  boxShadow: TV.shadow(ctx),
                ),
                child: QrImageView(
                  data: url,
                  size: 132,
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
              const SizedBox(height: 10),
              Text(url,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: scheme.outline)),
            ],
          ),
        ),
      );
    },
  );
}
