import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/library_controller.dart';

/// 发布到网站。
///
/// 这里是整条商业链路的最后一段: 导出 -> 发布 -> 拿到永久公开链接 -> 分享。
///
/// 账号连接走**设备码**: App 显示一串短码，用户在网页上敲进去确认，
/// 令牌由服务器直接发到这台机器。App 从头到尾不碰用户密码，
/// 令牌也不经过用户的剪贴板。
class PublishDialog extends StatefulWidget {
  final LibraryController c;
  const PublishDialog({super.key, required this.c});

  static Future<void> show(BuildContext context, LibraryController c) =>
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => PublishDialog(c: c));

  @override
  State<PublishDialog> createState() => _PublishDialogState();
}

class _PublishDialogState extends State<PublishDialog> {
  String visibility = 'public';

  @override
  void initState() {
    super.initState();
    widget.c.addListener(_tick);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.c.removeListener(_tick);
    super.dispose();
  }

  Future<void> _open(String url) async {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    }
  }

  Future<void> _publish() async {
    await widget.c.publishStory(visibility: visibility);
  }

  String get _base =>
      widget.c.settings.siteUrl.trim().replaceAll(RegExp(r'/+$'), '');

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final scheme = Theme.of(context).colorScheme;
    final export = c.lastExport;
    final done = c.lastPublish;

    return AlertDialog(
      title: const Text('发布到网站'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (export == null)
                _hint(scheme,
                    '还没有导出。先点「导出 Story 网页」，发布上传的就是那份产物。')
              else
                _hint(scheme,
                    '将上传 ${export.photoCount} 张网页用图'
                    '（${(export.totalBytes / 1024 / 1024).toStringAsFixed(1)} MB）。'
                    '原图一张都不会离开这台电脑。'),
              const SizedBox(height: 16),
              const SizedBox(height: 12),
              _account(scheme),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(
                      value: 'public',
                      label: Text('公开', style: TextStyle(fontSize: 12))),
                  ButtonSegment(
                      value: 'unlisted',
                      label: Text('仅凭链接访问',
                          style: TextStyle(fontSize: 12))),
                ],
                selected: {visibility},
                onSelectionChanged: (v) =>
                    setState(() => visibility = v.first),
              ),
              if (c.hasPublished && done == null) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Icon(Icons.sync, size: 14, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '这趟行程已经发布过。再次发布是更新那一篇: '
                      '链接不变，也不会再扣一次额度。',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ),
                  TextButton(
                    onPressed: c.publishing ? null : c.forgetPublished,
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero),
                    child: const Text('改为新建一篇',
                        style: TextStyle(fontSize: 11)),
                  ),
                ]),
              ],
              if (c.publishing) ...[
                const SizedBox(height: 18),
                LinearProgressIndicator(
                    value: c.publishTotal == 0
                        ? null
                        : c.publishDone / c.publishTotal),
                const SizedBox(height: 8),
                Text(c.status, style: const TextStyle(fontSize: 12)),
              ],
              if (done != null) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          done.updated
                              ? '已更新，链接没有变'
                              : '已发布，这个链接永久有效',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      SelectableText(done.publicUrl,
                          style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(children: [
                        TextButton.icon(
                          onPressed: () => Clipboard.setData(
                              ClipboardData(text: done.publicUrl)),
                          icon: const Icon(Icons.copy, size: 15),
                          label: const Text('复制链接',
                              style: TextStyle(fontSize: 12)),
                        ),
                        TextButton.icon(
                          onPressed: () => _open(done.publicUrl),
                          icon: const Icon(Icons.open_in_new, size: 15),
                          label: const Text('打开',
                              style: TextStyle(fontSize: 12)),
                        ),
                        TextButton.icon(
                          // Facebook 只认公开地址，所以这一步必须在发布之后
                          onPressed: () => _open(
                              'https://www.facebook.com/sharer/sharer.php?u='
                              '${Uri.encodeComponent(done.publicUrl)}'),
                          icon: const Icon(Icons.share, size: 15),
                          label: const Text('分享到 Facebook',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text('微信要用二维码转发 —— 打开上面的网页，'
                          '页面底部有「微信」按钮，扫码即可。',
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
              if (c.needsPayment) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('还没有可用的发布额度',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text('照片和文字都还在这台电脑上，付款后回来再点一次发布即可。',
                          style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: () => _open(
                            '$_base/pricing'),
                        icon: const Icon(Icons.open_in_new, size: 15),
                        label: const Text('去网站购买',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ] else if (c.lastError != null && !c.publishing) ...[
                const SizedBox(height: 14),
                Text(c.lastError!,
                    style: TextStyle(fontSize: 12, color: scheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: c.publishing ? null : () => Navigator.pop(context),
          child: Text(done == null ? '取消' : '完成'),
        ),
        FilledButton(
          onPressed: (c.publishing || export == null || !c.isLinked)
              ? null
              : _publish,
          child: Text(c.hasPublished || done != null ? '更新' : '发布'),
        ),
      ],
    );
  }

  /// 账号连接区。三种状态: 没连、正在等用户确认、已连。
  Widget _account(ColorScheme scheme) {
    final c = widget.c;
    final start = c.linkStart;

    if (start != null) {
      // 正在等用户去网页确认
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('在网页上输入这串码',
                style:
                    TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SelectableText(
              start.userCode,
              style: const TextStyle(
                  fontSize: 30, letterSpacing: 6, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton.tonalIcon(
                onPressed: () => _open(start.verifyUrl),
                icon: const Icon(Icons.open_in_new, size: 15),
                label: const Text('打开确认页',
                    style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: c.cancelDeviceLink,
                child: const Text('取消', style: TextStyle(fontSize: 12)),
              ),
              const Spacer(),
              Text('${c.linkSecondsLeft}s',
                  style: TextStyle(fontSize: 11, color: scheme.outline)),
            ]),
            const SizedBox(height: 4),
            Text('确认后这里会自动登录，不用回来点任何按钮。',
                style:
                    TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    if (c.isLinked) {
      return Row(children: [
        Icon(Icons.check_circle, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        const Expanded(
          child: Text('账号已连接', style: TextStyle(fontSize: 12)),
        ),
        TextButton(
          onPressed: () => _open('$_base/account'),
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero),
          child: const Text('账户页', style: TextStyle(fontSize: 11)),
        ),
        TextButton(
          onPressed: c.publishing ? null : c.unlinkDevice,
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero),
          child: const Text('断开', style: TextStyle(fontSize: 11)),
        ),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          FilledButton.icon(
            onPressed: c.linking ? null : c.startDeviceLink,
            icon: const Icon(Icons.link, size: 16),
            label: Text(c.linking ? '正在连接...' : '连接账号',
                style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _open('$_base/signup'),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero),
            child: const Text('还没有账号？免费注册',
                style: TextStyle(fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 6),
        Text('会显示一串短码，在网页上敲进去确认即可。App 不需要你的密码。',
            style: TextStyle(fontSize: 11, color: scheme.outline)),
        if (c.linkError != null) ...[
          const SizedBox(height: 6),
          Text(c.linkError!,
              style: TextStyle(fontSize: 11, color: scheme.error)),
        ],
      ],
    );
  }

  Widget _hint(ColorScheme scheme, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12, height: 1.5)),
      );
}
