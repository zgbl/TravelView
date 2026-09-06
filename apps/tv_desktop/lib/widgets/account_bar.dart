import 'dart:io';

import 'package:flutter/material.dart';

import '../state/library_controller.dart';

/// 账号状态，常驻主界面顶栏。
///
/// **登录不该埋在发布对话框里。** 用户挑完照片、点了发布，才发现要先连账号，
/// 这时候他的注意力在"我的照片"上，被打断去处理账号是最糟的时机。
/// 放在顶栏，他任何时候都能顺手连上，发布时就只剩发布这一件事。
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
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    // 连上了就把弹出的连接框关掉
    final nav = Navigator.of(context, rootNavigator: true);
    if (widget.c.isLinked && _dialogOpen && nav.canPop()) {
      _dialogOpen = false;
      nav.pop();
    }
  }

  bool _dialogOpen = false;

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

  String get _base =>
      widget.c.settings.siteUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Future<void> _connect() async {
    _dialogOpen = true;
    widget.c.startDeviceLink();      // 不 await: 它会一直轮询到用户确认
    await showDialog<void>(
      context: context,
      builder: (_) => _LinkDialog(c: widget.c, open: _open),
    );
    _dialogOpen = false;
    widget.c.cancelDeviceLink();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final scheme = Theme.of(context).colorScheme;

    if (!c.isLinked) {
      return TextButton.icon(
        onPressed: c.linking ? null : _connect,
        icon: const Icon(Icons.login, size: 15),
        label: const Text('登录', style: TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: Size.zero),
      );
    }

    return PopupMenuButton<String>(
      tooltip: '账号',
      onSelected: (v) {
        if (v == 'account') _open('$_base/account');
        if (v == 'stories') _open('$_base/stories');
        if (v == 'logout') c.unlinkDevice();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'account', child: Text('账户页')),
        PopupMenuItem(value: 'stories', child: Text('我发布的故事')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'logout', child: Text('退出登录')),
      ],
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle, size: 14, color: scheme.primary),
        const SizedBox(width: 5),
        const Text('已登录', style: TextStyle(fontSize: 12)),
        const Icon(Icons.arrow_drop_down, size: 16),
      ]),
    );
  }
}

/// 连接对话框: 显示短码，等用户去网页确认。
class _LinkDialog extends StatefulWidget {
  final LibraryController c;
  final Future<void> Function(String url) open;
  const _LinkDialog({required this.c, required this.open});

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  @override
  void initState() {
    super.initState();
    widget.c.addListener(_tick);
  }

  void _tick() => mounted ? setState(() {}) : null;

  @override
  void dispose() {
    widget.c.removeListener(_tick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final scheme = Theme.of(context).colorScheme;
    final start = c.linkStart;

    return AlertDialog(
      title: const Text('登录'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (start == null && c.linkError == null) ...[
              const Row(children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('正在获取登录码...', style: TextStyle(fontSize: 13)),
              ]),
            ] else if (start != null) ...[
              const Text('在浏览器里输入这串码，就登录好了',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 14),
              Center(
                child: SelectableText(
                  start.userCode,
                  style: const TextStyle(
                      fontSize: 34,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                FilledButton.icon(
                  onPressed: () => widget.open(start.verifyUrl),
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: const Text('打开网页', style: TextStyle(fontSize: 12)),
                ),
                const Spacer(),
                Text('${c.linkSecondsLeft}s',
                    style: TextStyle(fontSize: 11, color: scheme.outline)),
              ]),
              const SizedBox(height: 10),
              Text('确认后这个窗口会自己关掉，不用回来点任何按钮。',
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
            if (c.linkError != null) ...[
              const SizedBox(height: 10),
              Text(c.linkError!,
                  style: TextStyle(fontSize: 12, color: scheme.error)),
              const SizedBox(height: 10),
              TextButton(
                onPressed: c.linking ? null : c.startDeviceLink,
                child: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
