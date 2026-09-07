import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tv_core/tv_core.dart';

import '../state/library_controller.dart';
import 'account_bar.dart';

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
    // 后台拉一次已发布列表 —— 有了它才能提示"你之前发过日期重叠的一篇"
    if (widget.c.isLinked) widget.c.loadRemoteStories();
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

  /// 让用户从"我已发布的故事"里挑一篇来覆盖。
  /// 列表来自服务器，所以换台电脑、重建草稿之后照样能找回自己的东西。
  Future<void> _pickStory() async {
    final c = widget.c;
    await c.loadRemoteStories();
    if (!mounted) return;
    final picked = await showDialog<RemoteStory>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更新我已发布的哪一篇？'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: c.remoteStories.isEmpty
              ? Center(
                  child: Text(c.lastError ?? '还没有发布过任何故事',
                      style: const TextStyle(fontSize: 13)))
              : ListView.separated(
                  itemCount: c.remoteStories.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = c.remoteStories[i];
                    return ListTile(
                      dense: true,
                      title: Text(s.title,
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        '${s.start ?? ''} - ${s.end ?? ''} · '
                        '${s.stops} 站 · ${s.photos} 张'
                        '${s.published ? '' : ' · 未发布完'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: () => Navigator.pop(ctx, s),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
        ],
      ),
    );
    if (picked != null) c.pickStoryToUpdate(picked);
  }

  Future<void> _publish() async {
    // 覆盖是不可撤销的，而且被覆盖的链接可能已经发给别人了。
    // 这一步问一次，代价是一次点击，省掉的是"我的游记没了"
    if (widget.c.updateExisting) {
      final target = widget.c.pickedStoryUrl.isNotEmpty
          ? widget.c.pickedStoryUrl
          : widget.c.publishedUrl;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('覆盖已发布的那一篇？'),
          content: Text(
            '$target\n\n'
            '这个地址上现在的内容会被这次的内容替换掉，无法撤销。'
            '已经分享出去的链接仍然有效，但别人看到的会是新内容。',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认覆盖')),
          ],
        ),
      );
      if (ok != true) return;
    }
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
                // 说清楚"张"和"个文件"不是一回事。
                // 进度条数的是文件数（每张照片一张大图 + 一张缩略图），
                // 这里只写"张"的话，用户会以为我们在偷偷传三倍的东西
                _hint(scheme,
                    '将上传 ${export.photoCount} 张照片'
                    '（每张一份 1600px 网页图 + 一份 480px 缩略图，'
                    '共 ${export.photoCount * 2 + 1} 个文件，'
                    '${(export.totalBytes / 1024 / 1024).toStringAsFixed(1)} MB）。'
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
              // ── 这次是发新的一篇，还是更新已有的那一篇 ──
              //
              // **默认永远是发新的一篇。** "更新"会覆盖掉一个可能已经
              // 分享给别人的链接，这种破坏性动作不该是默认值，
              // 更不该在内容根本不是同一趟行程时出现。
              // ── 这次是发新的一篇，还是更新已有的那一篇 ──
              //
              // **默认永远是发新的一篇。** "更新"会覆盖掉一个可能已经
              // 分享给别人的链接，这种破坏性动作不该是默认值。
              // 但**必须永远有一条路能更新** —— 草稿里那条记录会断，
              // 断了还不给挑，用户就只能重发一篇、旧链接烂在外面。
              if (done == null) ...[
                const SizedBox(height: 14),
                if (c.pickedStoryId.isNotEmpty)
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
                        const Text('将覆盖这一篇：',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(c.pickedStoryTitle,
                            style: const TextStyle(fontSize: 13)),
                        Text(c.pickedStoryUrl,
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant)),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: c.publishing
                                ? null
                                : () => c.pickStoryToUpdate(null),
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero),
                            child: const Text('改回发新的一篇',
                                style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (c.canUpdatePublished)
                  CheckboxListTile(
                    value: c.updateExisting,
                    onChanged: c.publishing
                        ? null
                        : (v) => c.setUpdateExisting(v ?? false),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('更新已发布的那一篇（不新发）',
                        style: TextStyle(fontSize: 12)),
                    subtitle: Text(
                      c.updateExisting
                          ? '会覆盖 ${c.publishedUrl} 的内容，链接不变，不扣额度'
                          : '不勾就是发新的一篇，之前那一篇不受影响',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  )
                else if (c.updateCandidates.isNotEmpty) ...[
                  // 日期有重叠 = 很可能就是同一趟行程的另一个版本。
                  // **只提示，不替用户选** —— 覆盖不可撤销，猜错代价太大
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '你之前发布过日期重叠的 ${c.updateCandidates.length} 篇，'
                          '这次可能是想更新它？',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        ...c.updateCandidates.take(3).map((st) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(children: [
                                Expanded(
                                  child: Text(
                                    '${st.title}   ${st.start ?? ''} - '
                                    '${st.end ?? ''} · ${st.photos} 张',
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                TextButton(
                                  onPressed: c.publishing
                                      ? null
                                      : () => c.pickStoryToUpdate(st),
                                  style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      minimumSize: Size.zero),
                                  child: const Text('更新这一篇',
                                      style: TextStyle(fontSize: 11)),
                                ),
                              ]),
                            )),
                        Text('不选的话就是发新的一篇，那些都不会被改动。',
                            style: TextStyle(
                                fontSize: 11, color: scheme.outline)),
                      ],
                    ),
                  ),
                ]
                else
                  Text('会发布成新的一篇。',
                      style: TextStyle(fontSize: 12, color: scheme.outline)),
                if (c.pickedStoryId.isEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: c.publishing || !c.isLinked
                          ? null
                          : _pickStory,
                      icon: const Icon(Icons.history, size: 15),
                      label: const Text('改为更新我已发布的某一篇...',
                          style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: Size.zero),
                    ),
                  ),
              ],
              if (c.publishing) ...[
                const SizedBox(height: 18),
                LinearProgressIndicator(
                    value: c.publishTotal == 0
                        ? null
                        : c.publishDone / c.publishTotal),
                const SizedBox(height: 8),
                Text(c.status, style: const TextStyle(fontSize: 12)),
                Text('进度按文件数算，不是照片数',
                    style: TextStyle(fontSize: 11, color: scheme.outline)),
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
                if (c.canResume) ...[
                  const SizedBox(height: 6),
                  Text(
                    '已经传上去的照片不会重传，点「继续上传」只补没传完的那些。'
                    '不会再建一篇，也不会再扣一次额度。',
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
                ],
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
          child: Text(c.canResume
              ? '继续上传'
              : c.updateExisting
                  ? '更新那一篇'
                  : '发布新的一篇'),
        ),
      ],
    );
  }

  /// 账号状态。没登录就在这儿直接登录，不用跑回主界面。
  Widget _account(ColorScheme scheme) {
    final c = widget.c;

    if (c.isLinked) {
      return Row(children: [
        Icon(Icons.check_circle, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        const Expanded(
          child: Text('已登录', style: TextStyle(fontSize: 12)),
        ),
        TextButton(
          onPressed: () => _open('$_base/account'),
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero),
          child: const Text('账户页', style: TextStyle(fontSize: 11)),
        ),
        TextButton(
          onPressed: c.publishing ? null : c.logout,
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero),
          child: const Text('退出登录', style: TextStyle(fontSize: 11)),
        ),
      ]);
    }

    return Row(children: [
      FilledButton.icon(
        onPressed: () => LoginDialog.show(context, c),
        icon: const Icon(Icons.login, size: 16),
        label: const Text('登录', style: TextStyle(fontSize: 12)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text('发布需要先登录',
            style: TextStyle(fontSize: 11, color: scheme.outline)),
      ),
    ]);
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
