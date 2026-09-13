import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

/// 我发布过的故事，**在 App 里列出来、在 App 里打开**。
///
/// 以前这个菜单项直接把系统浏览器顶到前台。可用户点它的时候是在
/// TravelView 里干活，想的是"看一眼我上次发的那篇"，不是"离开这个程序"。
class StoriesPage extends StatefulWidget {
  final PublishConfig config;
  const StoriesPage({super.key, required this.config});

  static Future<void> show(BuildContext context, PublishConfig config) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => StoriesPage(config: config)));

  @override
  State<StoriesPage> createState() => _StoriesPageState();
}

class _StoriesPageState extends State<StoriesPage> {
  late final StoriesStore _store = StoriesStore(widget.config);

  @override
  void initState() {
    super.initState();
    _store.addListener(_tick);
    _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  Future<void> _openInBrowser(String url) async {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    }
  }

  void _read(RemoteStory s) => StoryViewerPage.open(
        context,
        () => StoryBundle.openUrl(s.url),
        onShare: (ctx, url) async {
          await Clipboard.setData(ClipboardData(text: url));
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx)
                .showSnackBar(SnackBar(content: Text(tr('链接已复制'))));
          }
        },
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = _store.stories;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('我发布的故事')),
        actions: [
          IconButton(
            tooltip: tr('刷新'),
            onPressed: _store.loading ? null : _store.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: switch ((list, _store.error)) {
        (null, final e?) => _center(Text(e)),
        (null, _) => _center(const CircularProgressIndicator()),
        (final l?, _) when l.isEmpty =>
          _center(Text(tr('还没有发布过故事'),
              style: TextStyle(color: scheme.outline))),
        (final l?, _) => GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 280,
              mainAxisExtent: 210,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
            ),
            itemCount: l.length,
            itemBuilder: (_, i) => _card(l[i]),
          ),
      },
    );
  }

  Widget _center(Widget child) => Center(child: child);

  Widget _card(RemoteStory s) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _read(s),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              Image.network(
                _store.coverUrl(s),
                fit: BoxFit.cover,
                // 封面取不到不代表这篇坏了 —— 退回一块安静的底就行
                errorBuilder: (_, __, ___) =>
                    ColoredBox(color: scheme.surfaceContainerHighest),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: IconButton(
                  tooltip: tr('在浏览器里打开'),
                  iconSize: 16,
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.black38,
                      foregroundColor: Colors.white),
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () => _openInBrowser(s.url),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(trf('{0} 张照片', [s.photos]),
                    style: TextStyle(fontSize: 11, color: scheme.outline)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
