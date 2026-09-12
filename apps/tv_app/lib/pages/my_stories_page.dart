import 'package:flutter/material.dart';
import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

import '../state/session.dart';
import '../state/stories_store.dart';
import '../ui/theme.dart';
import '../widgets/share_sheet.dart';

/// 首页：**我发布过的东西。**
///
/// 登录之后第一眼该看见自己的作品。已经发过几篇的人回来，八成是想
/// 再看一眼、或者把链接再发给谁 —— 让他为此先等一遍相册扫描没道理。
/// 相册扫描只在「新建」里发生。
class MyStoriesPage extends StatefulWidget {
  final Session session;
  const MyStoriesPage(this.session, {super.key});

  @override
  State<MyStoriesPage> createState() => _MyStoriesPageState();
}

class _MyStoriesPageState extends State<MyStoriesPage> {
  late final StoriesStore _store = StoriesStore(widget.session.account.config);
  final _search = TextEditingController();
  StorySort _sort = StorySort.newest;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    _search.dispose();
    super.dispose();
  }

  void _onStore() => setState(() {});

  List<RemoteStory> get _visible {
    final all = _store.stories ?? const <RemoteStory>[];
    final q = _search.text.trim().toLowerCase();
    final hit = q.isEmpty
        ? all
        : all.where((s) {
            // 标题、日期、链接都能搜到 —— 用户记得住哪个是哪个，
            // 但记不住我们把它归到哪个字段
            final hay = '${s.title} ${s.start ?? ''} ${s.end ?? ''} ${s.slug}';
            return hay.toLowerCase().contains(q);
          }).toList();
    return _sort.apply(hit);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('我的回顾')),
        actions: [
          PopupMenuButton<StorySort>(
            icon: const Icon(Icons.swap_vert),
            tooltip: tr('排序'),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              for (final s in StorySort.values)
                PopupMenuItem(value: s, child: Text(tr(s.label))),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _store.load,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_store.stories == null && _store.loading) {
      return const Center(
        child: SizedBox(
            width: 26, height: 26,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_store.stories == null && _store.error != null) {
      return _Scroll(children: [_ErrorState(_store.error!)]);
    }

    final list = _visible;
    final all = _store.stories ?? const <RemoteStory>[];

    return _Scroll(
      children: [
        if (all.length > 3 || _search.text.isNotEmpty) _searchBox(),
        if (all.isEmpty) const _EmptyState(),
        if (all.isNotEmpty && list.isEmpty) _noMatch(),
        for (final s in list)
          Padding(
            padding: const EdgeInsets.only(bottom: TV.gap),
            child: _StoryCard(
              story: s,
              store: _store,
              onRename: () => _rename(s),
              onDelete: () => _confirmDelete(s),
            ),
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _searchBox() => Padding(
        padding: const EdgeInsets.only(bottom: TV.gap),
        child: TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: tr('搜标题、日期'),
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(_search.clear),
                  ),
          ),
        ),
      );

  Widget _noMatch() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Text(tr('没有匹配的回顾'),
              style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        ),
      );

  Future<void> _rename(RemoteStory s) async {
    final ctrl = TextEditingController(text: s.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('重命名')),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('取消'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(tr('保存'))),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await _store.rename(s, name);
  }

  Future<void> _confirmDelete(RemoteStory s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('删除这篇回顾？')),
        // 说清楚代价。删除不退额度，这件事必须在按下之前告诉用户
        content: Text(tr('网页会立刻打不开，已经发出去的链接会失效。'
            '这不退回发布额度。')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('取消'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('删除')),
          ),
        ],
      ),
    );
    if (ok == true) await _store.remove(s);
  }
}

class _Scroll extends StatelessWidget {
  final List<Widget> children;
  const _Scroll({required this.children});

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(TV.pad, TV.gap, TV.pad, 0),
        children: children,
      );
}

/// 封面图卡片：大图 + 渐变蒙版 + 标题和统计压在图上。
class _StoryCard extends StatelessWidget {
  final RemoteStory story;
  final StoriesStore store;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _StoryCard({
    required this.story,
    required this.store,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(story.id),
      // 左滑删除、右滑重命名。**删除要再确认一次** ——
      // 手滑一下就没了的东西，用户不敢在这个列表里滑动
      background: _swipeBg(context, Alignment.centerLeft,
          Icons.drive_file_rename_outline, tr('重命名'),
          Theme.of(context).colorScheme.primary),
      secondaryBackground: _swipeBg(context, Alignment.centerRight,
          Icons.delete_outline, tr('删除'),
          Theme.of(context).colorScheme.error),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          onRename();
        } else {
          onDelete();
        }
        return false; // 真正的删除由 store 驱动列表刷新
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TV.rCard),
          boxShadow: TV.shadow(context),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(TV.rCard),
          child: Material(
            color: Theme.of(context).cardTheme.color,
            child: InkWell(
              onTap: () =>
                  showShareSheet(context, story.url, title: story.title),
              child: Stack(
                children: [
                  SizedBox(
                    height: 186,
                    width: double.infinity,
                    child: Image.network(
                      store.coverUrl(story),
                      fit: BoxFit.cover,
                      // 封面还没加载出来时给个中性底，不要闪白
                      loadingBuilder: (c, child, p) => p == null
                          ? child
                          : Container(
                              color: Theme.of(c)
                                  .colorScheme
                                  .surfaceContainerHighest),
                      // 取不到封面时**不要摆一个碎图图标** —— 那看起来像
                      // "你这篇游记坏了"，而实际上坏的只是一张预览图。
                      // 退回一块安静的渐变底，标题照常压在上面，
                      // 这张卡片依然是完整的。
                      errorBuilder: (c, _, __) => DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Theme.of(c).colorScheme.primaryContainer,
                              Theme.of(c).colorScheme.surfaceContainerHighest,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(gradient: TV.scrim),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          story.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (story.start != null)
                              _Tag(Icons.event, _date(story.start!)),
                            _Tag(Icons.place_outlined,
                                trf('{0} 站', [story.stops])),
                            _Tag(Icons.photo_outlined,
                                trf('{0} 张', [story.photos])),
                            if (story.updates > 0)
                              _Tag(Icons.history,
                                  trf('更新 {0} 次', [story.updates])),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _swipeBg(BuildContext context, Alignment align, IconData icon,
      String label, Color color) {
    return Container(
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(TV.rCard),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  static String _date(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : '${d.year}.${d.month}.${d.day}';
  }
}

/// 压在照片上的半透明小标签
class _Tag extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Tag(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(TV.rChip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text(text,
                style: const TextStyle(color: Colors.white, fontSize: 11.5)),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 70),
      child: Column(
        children: [
          // 一个用代码画的地图别针 + 路线，不引图片资源
          SizedBox(
            width: 132,
            height: 112,
            child: CustomPaint(painter: _RoutePainter(scheme.primary)),
          ),
          const SizedBox(height: 22),
          Text(tr('还没有发布过回顾'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Text(
              tr('从相册里挑一趟旅行，几分钟就能得到一个可以发给别人的链接。'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.outline, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 空状态的插画：一条虚线路线加三个点。
class _RoutePainter extends CustomPainter {
  final Color color;
  _RoutePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.1, size.height * 0.78)
      ..cubicTo(size.width * 0.34, size.height * 0.42, size.width * 0.5,
          size.height * 0.95, size.width * 0.9, size.height * 0.22);

    final line = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // 虚线：手动切片，比引一个包省事
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, (d + 9).clamp(0, m.length)), line);
        d += 16;
      }
    }

    final dot = Paint()..color = color;
    for (final t in [0.0, 0.55, 1.0]) {
      for (final m in path.computeMetrics()) {
        final pos = m.getTangentForOffset(m.length * t)?.position;
        if (pos == null) continue;
        canvas.drawCircle(pos, t == 1.0 ? 7 : 5, dot);
        canvas.drawCircle(
            pos,
            t == 1.0 ? 3 : 2,
            Paint()..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) => old.color != color;
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState(this.message);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 90),
      child: Column(
        children: [
          Icon(Icons.cloud_off, size: 40, color: scheme.outline),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(tr('下拉可以重试'),
              style: TextStyle(fontSize: 12, color: scheme.outline)),
        ],
      ),
    );
  }
}
