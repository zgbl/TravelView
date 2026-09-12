import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

import '../state/music_store.dart';
import '../state/selection.dart';
import '../state/story_draft.dart';
import '../state/trips.dart';
import '../ui/theme.dart';
import '../widgets/asset_thumb.dart';
import 'generate_page.dart';
import 'photo_viewer.dart';

/// 一趟行程：**照片**和**地图**两个 tab。
///
/// 挑图就在照片这个 tab 里，不另开一个"挑选模式"页面 ——
/// 手机上每多一层页面，用户就多一次"我现在在哪"的困惑。
class TripPage extends StatefulWidget {
  final Trip trip;
  const TripPage(this.trip, {super.key});

  @override
  State<TripPage> createState() => _TripPageState();
}

class _TripPageState extends State<TripPage> {
  late final TripSelection _sel = TripSelection(widget.trip.photos);
  late final StoryDraft _draft = StoryDraft(
      defaultTitle: '${widget.trip.start.year}.'
          '${widget.trip.start.month}.${widget.trip.start.day}');

  /// **一进来就把站点算好。**
  ///
  /// 桌面端的编辑页就是按站组织的：一站一张卡片，照片在上、文字在下。
  /// 手机端没有理由换一套 —— 同一个人在两个屏幕上做的是同一件事，
  /// 换个组织方式只会让他重新学一遍。
  ///
  /// `buildRoute` 是纯计算，几千张也就几十毫秒，不值得为它加个加载态。
  late final TripRoute _route = buildRoute(widget.trip.photos);

  int _tab = 0;

  /// 从预览页回来要滚到哪一站 —— 每一站一个 key。
  /// **这是"回去继续编辑"能成立的关键**：把人送回一个 2000 像素长的
  /// 页面顶部，等于让他自己再找一遍第三站在哪。
  final Map<int, GlobalKey> _stopKeys = {};
  final ScrollController _scroll = ScrollController();

  GlobalKey _keyFor(int seq) =>
      _stopKeys.putIfAbsent(seq, () => GlobalKey());

  @override
  void dispose() {
    _scroll.dispose();
    _sel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sel,
      builder: (context, _) => PopScope(
        // 多选状态下按返回键先退出多选，不要直接退出这趟行程 ——
        // 挑了半天一个后退全没了，是最气人的那种交互
        canPop: !_sel.selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _sel.exitSelecting();
        },
        child: Scaffold(
          appBar: _sel.selecting ? _selectingBar() : _normalBar(),
          // 输入法弹出来时要把正在写的那一行顶上去，不能盖住
          resizeToAvoidBottomInset: true,
          body: _tab == 0
              ? _Timeline(widget.trip, _route, _sel, _draft, _scroll, _keyFor)
              : _TripMap(widget.trip, _sel),
          // **挑图的操作全部在屏幕下半部。**
          // 竖握手机时拇指扫得到的只有底下三分之一，把勾选和批量操作
          // 放到顶部的 AppBar 里，等于要用户换手或者挪握姿 —— 挑三百张
          // 照片的过程中每一次都要挪，这是最伤的那种设计。
          bottomNavigationBar: _sel.selecting ? _selectingBottomBar() : _tabBar(),
          floatingActionButton: _sel.selecting ? null : _generateButton(),
        ),
      ),
    );
  }

  AppBar _normalBar() => AppBar(title: Text(_title()));

  /// 多选时顶部**只报数，不放按钮** —— 数字是用来看的，按钮是用来点的，
  /// 只有前者适合放在够不着的地方。
  AppBar _selectingBar() => AppBar(
        automaticallyImplyLeading: false,
        title: Text(trf('已选 {0} / {1}', [_sel.count, _sel.total])),
      );

  Widget _tabBar() => NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.photo_outlined), label: tr('照片')),
          NavigationDestination(
              icon: const Icon(Icons.map_outlined), label: tr('地图')),
        ],
      );

  /// 多选时的底部操作条。三个大按钮，都在拇指扫得到的范围里。
  Widget _selectingBottomBar() {
    final allPicked = _sel.count == _sel.total;
    return SafeArea(
      top: false,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          border: Border(
            top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: _BarButton(
                icon: allPicked ? Icons.deselect : Icons.select_all,
                label: allPicked ? tr('全不选') : tr('全选'),
                onTap: allPicked ? _sel.pickNone : _sel.pickAll,
              ),
            ),
            Expanded(
              child: _BarButton(
                icon: Icons.done_all,
                label: tr('挑完了'),
                onTap: _sel.exitSelecting,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _generateButton() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 进多选的入口放在生成按钮上面，同样在拇指区。
          // 长按照片也能进，但那是老手才会发现的路。
          FloatingActionButton.small(
            heroTag: 'pick',
            tooltip: tr('挑选照片'),
            onPressed: _sel.enterSelecting,
            child: const Icon(Icons.check_circle_outline),
          ),
          const SizedBox(height: 10),
          _fab(),
        ],
      );

  Widget _fab() => FloatingActionButton.extended(
        onPressed: _sel.isEmpty ? null : _openPreview,
        heroTag: 'go',
        icon: const Icon(Icons.auto_awesome),
        label: Text(_sel.isEmpty
            ? tr('一张都没选')
            : trf('生成回顾 · {0} 张', [_sel.count])),
      );

  /// 去预览，**并且准备好把人接回来。**
  ///
  /// 预览页不是终点。用户在那儿看出问题时要能原路回到出问题的地方 ——
  /// 它退回来时带一个 [PreviewExit]，说清楚回来以后停在哪儿。
  Future<void> _openPreview() async {
    final exit = await Navigator.of(context).push<PreviewExit>(
      MaterialPageRoute(
        builder: (_) => GeneratePage(sel: _sel, draft: _draft),
      ),
    );
    if (!mounted || exit == null) return;

    // 要改照片就直接进多选 —— 让他回来还得自己再点一次那个按钮，
    // 是在惩罚一个已经表达过意图的人
    if (exit.reselect) {
      setState(() => _tab = 0);
      _sel.enterSelecting();
      return;
    }
    if (exit.toTop) {
      setState(() => _tab = 0);
      _scrollTop();
      return;
    }
    if (exit.stopSeq != null) {
      setState(() => _tab = 0);
      _scrollToStop(exit.stopSeq!);
    }
  }

  void _scrollTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut);
      }
    });
  }

  /// 滚到某一站。ListView 是懒构建的，目标还没建出来时拿不到 context ——
  /// 那种情况下退回顶部，**不能什么都不做**：一个按了没反应的按钮，
  /// 比没有这个按钮更让人怀疑自己点错了。
  void _scrollToStop(int seq) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _stopKeys[seq]?.currentContext;
      if (ctx == null) {
        _scrollTop();
        return;
      }
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.04,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    });
  }

  String _title() {
    final s = widget.trip.start;
    return '${s.year}.${s.month}.${s.day} · ${trf('{0} 天', [
          widget.trip.days
        ])}';
  }
}

/// 按**站**组织，和桌面端一模一样：一站一张卡片，照片在上、文字在下。
///
/// 桌面端那份代码里写着"先看照片，再写字，顺序是对的" —— 就是这个意思：
/// 人要先看见那张茶园的照片，才想得起来"上山的路结了冰"。
/// 把文字框挪到另一页、或者挪到照片前面，写出来的都是流水账。
class _Timeline extends StatelessWidget {
  final Trip trip;
  final TripRoute route;
  final TripSelection sel;
  final StoryDraft draft;
  final ScrollController controller;
  final GlobalKey Function(int seq) keyFor;
  const _Timeline(this.trip, this.route, this.sel, this.draft, this.controller,
      this.keyFor);

  @override
  Widget build(BuildContext context) {
    final byId = {for (final p in trip.photos) p.id: p};
    final stops = route.stays;

    // 没有位置信息的照片连不成站。**不能把它们丢掉** ——
    // 用户拍了就是拍了，只是我们不知道在哪儿，单独归一组放最后。
    final inStops = <String>{for (final s in stops) ...s.photoIds};
    final orphans =
        trip.photos.where((p) => !inStops.contains(p.id)).toList();

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: 2 + stops.length + (orphans.isEmpty ? 0 : 1),
      itemBuilder: (context, index) {
        if (index == 0) return _TitleBlock(draft);
        // 配乐紧跟在标题下面。**和桌面端放在同一个位置**（那一栏
        // "这篇怎么呈现"里）—— 它和标题、副标题是同一类东西：
        // 定一次就不再动的"这一篇长什么样"，不是"现在要做什么"。
        if (index == 1) return _MusicRow(draft);

        final i = index - 2;
        if (i < stops.length) {
          final stop = stops[i];
          final photos = stop.photoIds
              .map((id) => byId[id])
              .whereType<PhotoRecord>()
              .toList();
          return _StopSection(
            key: keyFor(stop.seq),
            stop: stop,
            index: i,
            photos: photos,
            trip: trip,
            sel: sel,
            draft: draft,
          );
        }

        return _StopSection(
          key: keyFor(-1),
          stop: null,
          index: stops.length,
          photos: orphans,
          trip: trip,
          sel: sel,
          draft: draft,
        );
      },
    );
  }
}

/// 一站：徽章 + 时间 + 照片网格 + 这一站的文字。
class _StopSection extends StatelessWidget {
  final Stop? stop;
  final int index;
  final List<PhotoRecord> photos;
  final Trip trip;
  final TripSelection sel;
  final StoryDraft draft;

  const _StopSection({
    super.key,
    required this.stop,
    required this.index,
    required this.photos,
    required this.trip,
    required this.sel,
    required this.draft,
  });

  /// 没有位置的那一组用负数当 key，不会和真实站点撞上
  int get _seq => stop?.seq ?? -1;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final picked = photos.where((p) => sel.has(p.id)).length;
    final s = stop;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: s == null
                        ? scheme.surfaceContainerHighest
                        : scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    s == null ? tr('没有位置') : trf('第 {0} 站', [index + 1]),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: s == null
                          ? scheme.onSurfaceVariant
                          : scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (s != null)
                  Text(_timeLabel(s),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(trf('{0} / {1}', [picked, photos.length]),
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 10),

            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 3,
                crossAxisSpacing: 3,
              ),
              itemCount: photos.length,
              itemBuilder: (context, j) => _Tile(
                photo: photos[j],
                sel: sel,
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PhotoViewerPage(
                      trip.photos,
                      trip.photos.indexOf(photos[j]),
                      sel: sel,
                    ),
                  ),
                ),
              ),
            ),

            // 这一站的文字。**放在照片后面** —— 先看照片，再写字。
            const SizedBox(height: 12),
            TextFormField(
              initialValue: draft.stopNames[_seq],
              onChanged: (v) => draft.stopNames[_seq] = v,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                labelText: tr('小标题'),
                hintText: tr('例如 山顶的茶园'),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: draft.stopNotes[_seq],
              onChanged: (v) => draft.stopNotes[_seq] = v,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 5,
              style: const TextStyle(fontSize: 13, height: 1.5),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                labelText: tr('说明文字'),
                hintText: tr('这儿发生了什么'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _timeLabel(Stop s) {
    String hm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${s.arrive.month}月${s.arrive.day}日 ${hm(s.arrive)}';
  }
}

/// 整篇的标题和一句话，摆在第一站上面。
class _TitleBlock extends StatelessWidget {
  final StoryDraft draft;
  const _TitleBlock(this.draft);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: draft.title,
            onChanged: (v) => draft.title = v,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              isDense: true,
              hintText: trf('给这趟起个名字（默认 {0}）', [draft.defaultTitle]),
              border: InputBorder.none,
            ),
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
          TextFormField(
            initialValue: draft.subtitle,
            onChanged: (v) => draft.subtitle = v,
            textCapitalization: TextCapitalization.sentences,
            maxLines: null,
            decoration: InputDecoration(
              isDense: true,
              hintText: tr('一句话说说这趟'),
              border: InputBorder.none,
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// 这一篇的配乐。收起时只占一行，点开是一整张配乐设置面板。
///
/// **为什么不直接把设置摊在页面上**: 大多数游记是不配乐的，为此在每一趟
/// 行程的顶部常驻一张卡片，是在惩罚多数人。但也不能藏进某个二级菜单 ——
/// 藏起来等于没有这个功能。一行摘要 + 一个箭头，想加的人一眼看得到，
/// 不想加的人当它不存在。
class _MusicRow extends StatelessWidget {
  final StoryDraft draft;
  const _MusicRow(this.draft);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      // 面板里改了曲子，这一行要立刻跟着变 —— 不需要谁去 setState
      animation: draft,
      builder: (context, _) {
        final n = draft.music.length;
        final ok = draft.musicRightsOk;
        final summary = n == 0
            ? tr('没有配乐')
            : (ok ? trf('{0} 首 · 已声明', [n]) : trf('{0} 首 · 未声明', [n]));
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
          child: Material(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(TV.rCard),
            child: InkWell(
              borderRadius: BorderRadius.circular(TV.rCard),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (_) => _MusicSheet(draft),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(children: [
                  Icon(Icons.music_note,
                      size: 18, color: n == 0 ? scheme.outline : scheme.primary),
                  const SizedBox(width: 10),
                  Text(tr('配乐'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      summary,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          // 装了曲子却没声明，是**发布时会丢东西**的状态，
                          // 用错误色标出来，别让它混在灰色说明里
                          color: n > 0 && !ok ? scheme.error : scheme.outline),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right, size: 18, color: scheme.outline),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 服务器的单文件上限。**和 web/src/lib/storage.ts 里的 maxUploadBytes 是同一个数**，
/// 这里只是提前拦一次 —— 让用户传到 99% 才失败，比一开始就说清楚伤人得多。
const int _maxTrackBytes = 10 * 1024 * 1024;

class _MusicSheet extends StatefulWidget {
  final StoryDraft draft;
  const _MusicSheet(this.draft);

  @override
  State<_MusicSheet> createState() => _MusicSheetState();
}

class _MusicSheetState extends State<_MusicSheet> {
  /// 正在等系统选择器 / 正在拷文件。**防的是连点两下** ——
  /// 那会同时弹两个选择器，用户挑完第一首之后界面就乱了。
  bool _busy = false;

  StoryDraft get draft => widget.draft;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: AnimatedBuilder(
        animation: draft,
        builder: (context, _) {
          final n = draft.music.length;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trf('配乐（最多 {0} 首，轮流播放）', [StoryDraft.maxTracks]),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                // **我们不提供曲库。** 内置曲库选择永远太少，而且会让我们
                // 成为内容的提供方、版权责任落到我们头上。用户自己传，
                // 责任在上传者 —— 所以下面那个声明不是走过场。
                Text(
                  tr('曲子由你自己上传，我们不提供曲库，上传的人就是版权责任的承担人。'),
                  style: TextStyle(
                      fontSize: 12, height: 1.5, color: scheme.outline),
                ),
                const SizedBox(height: 16),

                for (final m in draft.music)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Icon(
                        StoryDraft.isLocalTrack(m)
                            ? Icons.music_note
                            : Icons.link,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(StoryDraft.trackLabel(m),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      IconButton(
                        tooltip: tr('去掉这一首'),
                        onPressed: _busy ? null : () => _remove(m),
                        icon: const Icon(Icons.close, size: 16),
                        visualDensity: VisualDensity.compact,
                      ),
                    ]),
                  ),

                if (n < StoryDraft.maxTracks)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _pickFile,
                          icon: const Icon(Icons.audio_file_outlined, size: 18),
                          label: Text(
                              n == 0 ? tr('选一个音频文件…') : tr('再加一首')),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _addLink,
                          child: Text(tr('用外部链接')),
                        ),
                      ],
                    ),
                  ),

                if (draft.music.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  // 版权声明。**增删任何一首都要重新勾** ——
                  // 一次勾选管到永远，等于没有声明
                  CheckboxListTile(
                    value: draft.musicRightsOk,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => draft.setMusicRights(v ?? false),
                    title: Text(
                      tr('这些音乐我拥有使用权，或它们允许商用/公开分享，由此产生的版权责任由我承担。'),
                      style: const TextStyle(fontSize: 12.5, height: 1.5),
                    ),
                  ),
                  Text(
                    tr('本地文件会随游记一起上传，删掉这篇游记时一并删除；外部链接的文件不在我们这儿，对方一旦失效就没声音了。'),
                    style: TextStyle(
                        fontSize: 11.5, height: 1.5, color: scheme.outline),
                  ),
                  if (!draft.musicRightsOk)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(tr('没有勾选声明，发布时不会带上配乐。'),
                          style: TextStyle(fontSize: 11.5, color: scheme.error)),
                    ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      tr('只在全屏播放时出声，默认静音，读者点一下才播。'),
                      style: TextStyle(
                          fontSize: 11.5, height: 1.5, color: scheme.outline),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 从系统选择器里挑一个音频文件。
  ///
  /// 挑完不直接加，**先弹一次版权警告**：曲子会跟着游记一起传到网上，
  /// 谁都能听、也能下载。用户按下"我确认"就等于完成了这一首的声明，
  /// 所以紧接着把那个勾选框也勾上。
  Future<void> _pickFile() async {
    setState(() => _busy = true);
    try {
      // 三个类型标识都要写，**少写一个那个平台上就形同虚设**:
      //   iOS / macOS 只认 UTI，Android 只认 mimeTypes 和 extensions，
      //   而 XTypeGroup 的过滤在缺项时是"什么都放行"。
      final group = XTypeGroup(
        // 这个 label 在部分平台的对话框里是**看得见的筛选器名字**，
        // 所以照样要过 tr()，不能写成裸中文
        label: tr('音频'),
        extensions: StoryDraft.audioExts,
        mimeTypes: const [
          'audio/mpeg', 'audio/mp4', 'audio/aac',
          'audio/ogg', 'audio/wav', 'audio/x-wav',
        ],
        // macUTIs 是同一个字段的旧名字，**两个都给会直接断言失败**
        uniformTypeIdentifiers: const ['public.audio'],
      );
      final f = await openFile(acceptedTypeGroups: [group]);
      if (f == null || !mounted) return;

      // 选择器按类型过滤只是"过滤器"，**不是闸门** ——
      // Android 上换个文件管理器就能挑到别的文件。真正的闸门在这里，
      // 以及 MusicStore.copyIn 和导出时的 StoryExporter 各再查一遍。
      final ext = p.extension(f.path).replaceAll('.', '').toLowerCase();
      if (!StoryDraft.audioExts.contains(ext)) {
        await _say(trf('只收 {0} 这几种格式，换个文件试试',
            [StoryDraft.audioExts.join(' / ')]));
        return;
      }

      final size = await File(f.path).length();
      if (!mounted) return;
      if (size > _maxTrackBytes) {
        await _say(trf('这个文件 {0}MB，超过了服务器 10MB 的单文件上限。配乐几 MB 就够 —— 读者要下完才有声音。',
            [(size / 1024 / 1024).round()]));
        return;
      }

      final ok = await _confirmRights(
        name: p.basename(f.path),
        detail: '${(size / 1024 / 1024).toStringAsFixed(1)} MB',
        fromLink: false,
      );
      if (ok != true || !mounted) return;

      // **先拷进沙盒再记路径。** 选择器给的是一个随时会被系统清掉的
      // 临时副本，只记它的话，用户挑完照片真正导出时文件已经没了
      final stored = await MusicStore.copyIn(f.path);
      if (!mounted) return;
      if (stored == null) {
        await _say(tr('这个文件读不到了，换一个试试'));
        return;
      }
      if (!draft.addMusic(stored)) {
        await MusicStore.remove(stored);
        if (mounted) await _say(tr('这首已经在里面了'));
        return;
      }
      draft.setMusicRights(true);
    } catch (e) {
      if (mounted) await _say('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 让用户贴一个音频直链。
  ///
  /// **只收 https 的音频文件直链，不收网页地址。** 用户很容易把
  /// Pixabay 的页面地址贴进来 —— 那是一个 HTML 页面，播放器拿到它
  /// 只会静静地不出声，而用户会以为是我们坏了。
  Future<void> _addLink() async {
    final ctl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('用一个外部链接作为配乐')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'https://…/song.mp3',
              helperText: tr('必须是 https 的音频文件直链（.mp3 / .m4a / .ogg），\n不是播放页面的网址'),
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            tr('音乐存在对方服务器上，我们不复制也不保存。好处是版权关系清楚；代价是对方一旦防盗链、改地址或删文件，这篇游记就永久没有声音了，而且你不会收到任何通知。'),
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(tr('取消'))),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
              child: Text(tr('用这个'))),
        ],
      ),
    );
    if (url == null || url.isEmpty || !mounted) return;
    if (!url.startsWith('https://')) {
      await _say(tr('只能用 https 开头的链接 —— http 会被浏览器整页拦掉'));
      return;
    }
    final ok = await _confirmRights(name: url, detail: null, fromLink: true);
    if (ok != true || !mounted) return;
    if (!draft.addMusic(url)) {
      await _say(tr('这首已经在里面了'));
      return;
    }
    draft.setMusicRights(true);
  }

  Future<void> _remove(String m) async {
    draft.removeMusic(m);
    // 沙盒里那份副本没有留着的理由了。**只删自己目录里的**，
    // MusicStore 会再确认一次，外链和别的路径碰都不碰
    await MusicStore.remove(m);
  }

  /// 上传前的版权警告。
  ///
  /// **这不是走过场。** 曲子一传上去，这篇游记里就有一份任何人
  /// 都能听到也能下载的音频，版权责任只能落在上传的人身上 ——
  /// 我们提供的是通道，不是曲库。所以每加一首都要他亲口确认一次，
  /// 而不是在一个角落里放一个默认勾上的小方框。
  Future<bool> _confirmRights({
    required String name,
    required String? detail,
    required bool fromLink,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('配乐的版权由你负责')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            if (detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(detail,
                    style: TextStyle(fontSize: 11, color: scheme.outline)),
              ),
            const SizedBox(height: 14),
            Text(
              fromLink
                  ? tr('这个链接会直接放给读者听，我们不为它的内容和存活兜底。请确认你拥有它的使用权，或者它允许商用/公开分享 —— 由此产生的版权责任由你承担。')
                  : tr('这段音频会跟着游记一起传到网上，任何人都能听到、也能下载。请确认你拥有它的使用权，或者它允许商用/公开分享 —— 由此产生的版权责任由你承担。'),
              style: const TextStyle(fontSize: 12.5, height: 1.6),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr('取消'))),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(tr('我确认，加进去'))),
        ],
      ),
    );
    return r == true;
  }

  /// 一句说清楚的提示。用对话框而不是 SnackBar —— 底下那张面板
  /// 盖住的就是 SnackBar 会出现的位置，弹在那儿等于没弹。
  Future<void> _say(String text) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(text, style: const TextStyle(height: 1.6)),
          actions: [
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(tr('好'))),
          ],
        ),
      );
}

class _Tile extends StatelessWidget {
  final PhotoRecord photo;
  final TripSelection sel;
  final VoidCallback onOpen;

  const _Tile({required this.photo, required this.sel, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final picked = sel.has(photo.id);
    final selecting = sel.selecting;

    return GestureDetector(
      // 多选状态下点击是勾选，平时点击是看大图。长按随时进多选。
      onTap: selecting ? () => sel.toggle(photo.id) : onOpen,
      onLongPress: () {
        sel.enterSelecting();
        if (!picked) sel.toggle(photo.id);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            // 没选中的压暗一档，一眼就能看出这一屏留下了什么
            child: Opacity(
              opacity: selecting && !picked ? 0.35 : 1,
              child: AssetThumb(photo.id),
            ),
          ),
          if (selecting)
            Positioned(
              right: 4,
              top: 4,
              child: _Check(picked),
            ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BarButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 21),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  final bool on;
  const _Check(this.on);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? scheme.primary : Colors.black26,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: on
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}

class _TripMap extends StatelessWidget {
  final Trip trip;
  final TripSelection sel;
  const _TripMap(this.trip, this.sel);

  @override
  Widget build(BuildContext context) {
    // 地图上画的是**选中的那些照片**的路线 —— 挑完图回来看一眼，
    // 就知道这一篇最后会走出什么形状
    final pts = sel.picked
        .where((p) => p.hasLocation)
        .map((p) => LatLng(p.lat!, p.lon!))
        .toList();

    if (pts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            tr('选中的照片里没有带位置的，画不出路线。'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      );
    }

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: pts,
          padding: const EdgeInsets.all(48),
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.travelview.app',
        ),
        PolylineLayer(polylines: [
          Polyline(points: pts, strokeWidth: 3, color: const Color(0xFF2E6F6A)),
        ]),
        MarkerLayer(
          markers: [
            for (final p in [pts.first, pts.last])
              Marker(
                point: p,
                width: 14,
                height: 14,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFF2E6F6A),
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                        BorderSide(color: Colors.white, width: 2)),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
