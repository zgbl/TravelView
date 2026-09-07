import 'package:flutter/material.dart';
import 'package:tv_core/tv_core.dart';

import '../state/library_controller.dart';
import '../widgets/ai_settings_dialog.dart';
import '../widgets/publish_dialog.dart';
import '../widgets/photo_tile.dart';
import '../widgets/stop_note_editor.dart';
import 'dart:io';

import 'photo_viewer.dart';

/// 生成旅行回顾：按「站」自动精选，用户确认或修改。
///
/// 核心交互是**两条并列的照片轨道**:
///   上面一条 = 这一站的全部照片
///   下面一条 = 精选进回顾的照片
/// 这样才能一眼看出"选了多少、漏了什么"，进而增删。
/// 只看精选结果是没法判断的 —— 那是之前最大的缺口。
class StoryPage extends StatefulWidget {
  final LibraryController c;
  const StoryPage({super.key, required this.c});

  @override
  State<StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends State<StoryPage> {
  TripRoute? route;

  /// 自动精选的**建议**（封面、重复分组、推荐张数都在里面）。
  /// 真正生效的选取状态存的是照片的 pick 标签 ——
  /// 这样和大图查看器里按空格是同一件事，也能持久保存。
  final Map<int, StopSelection> suggestions = {};
  int? expandedStop;
  int targetPerStop = 0; // 0 = 自动
  String _sig = '';

  @override
  void initState() {
    super.initState();
    widget.c.addListener(_onChanged);
    _recompute();
  }

  @override
  void dispose() {
    widget.c.removeListener(_onChanged);
    super.dispose();
  }

  String get _signature =>
      '${widget.c.rangeStart}|${widget.c.rangeEnd}|${widget.c.photoCount}'
      '|${widget.c.clusterPreset}';

  void _onChanged() {
    if (_signature != _sig) {
      _recompute();
    } else if (mounted) {
      // 选取状态变了（可能是在大图查看器里按的空格）—— 重建以更新两条轨道
      setState(() {});
    }
  }

  void _recompute() {
    _sig = _signature;
    final cat = widget.c.catalog;
    if (cat == null) return;
    final options = widget.c.clusterPreset == 'city'
        ? ClusterOptions.city
        : ClusterOptions.roadTrip;
    final r = buildRoute(widget.c.visiblePhotos, options: options);

    final curator = Curator(
      options: CurationOptions(
        targetCount: targetPerStop == 0 ? null : targetPerStop,
      ),
    );
    suggestions.clear();
    for (final stop in r.stays) {
      final photos = stop.photoIds
          .map(cat.byId)
          .whereType<PhotoRecord>()
          .toList()
        ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
      suggestions[stop.seq] = curator.curateStop(stop, photos);
    }
    setState(() => route = r);
  }

  List<PhotoRecord> _photosOf(Stop s) {
    final cat = widget.c.catalog;
    if (cat == null) return const [];
    return s.photoIds.map(cat.byId).whereType<PhotoRecord>().toList()
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  }

  List<PhotoRecord> _selectedOf(Stop stop) =>
      _photosOf(stop).where(widget.c.isPicked).toList();

  Future<void> _toggle(PhotoRecord r) => widget.c.togglePick(r);

  /// 把某一站的自动精选建议写成实际的选取。
  /// 这会覆盖这一站已有的手动选取，所以按钮上写清楚是"应用建议"。
  Future<void> _applySuggestion(Stop stop) async {
    final sug = suggestions[stop.seq];
    if (sug == null) return;
    await widget.c.applyPicks(
      photos: _photosOf(stop),
      pickedIds: sug.selected.map((e) => e.id).toSet(),
    );
  }

  Future<void> _clearStop(Stop stop) =>
      widget.c.applyPicks(photos: _photosOf(stop), pickedIds: const {});

  Future<void> _applyAll() async {
    final r = route;
    if (r == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('对全部站应用自动精选'),
        content: const Text(
          '会用自动精选的结果覆盖各站现有的选取，包括你手动选过的。\n'
          '照片本身不受影响。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('应用')),
        ],
      ),
    );
    if (ok != true) return;
    for (final stop in r.stays) {
      await _applySuggestion(stop);
    }
  }

  bool _fillingCaptions = false;

  /// 给所有**还没写过文字**的站按时间和地理信息自动补一段说明。
  /// 已经写过的一律不碰。
  Future<void> _fillCaptions() async {
    final r = route;
    if (r == null || _fillingCaptions) return;
    setState(() => _fillingCaptions = true);
    final n = await widget.c.fillEmptyCaptions(r);
    if (!mounted) return;
    setState(() => _fillingCaptions = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n == 0
          ? '每一站都已经有文字了，没有改动'
          : '已经为 $n 站生成文字，可以直接改'),
      duration: const Duration(seconds: 3),
    ));
  }

  /// 导出成可离线打开的 Story 网页包，然后直接在浏览器里打开给用户看。
  Future<void> _export() async {
    final r = route;
    if (r == null) return;
    final heroes = <int, String?>{};
    for (final stop in r.stays) {
      final sug = suggestions[stop.seq];
      final selected = _selectedOf(stop);
      if (selected.isEmpty) continue;
      heroes[stop.seq] = selected.any((e) => e.id == sug?.hero?.id)
          ? sug?.hero?.id
          : selected.first.id;
    }

    final title = widget.c.currentProjectName ?? '我的旅行';
    final cover = widget.c.coverPhotoId;
    // **只数真正进 Story 的站。** 副标题写 22 站、统计栏写 7 站，
    // 用户第一眼就会觉得数据是错的 —— 事实上错的是副标题。
    final shownStops =
        r.stays.where((s) => _selectedOf(s).isNotEmpty).length;
    final sub = '${_dateOnly(r.start)} - ${_dateOnly(r.end)}'
        ' · ${r.dayCount} 天 · $shownStops 站';

    final res = await widget.c.exportStory(
      trip: r,
      heroByStopSeq: heroes,
      coverPhotoId: cover.isEmpty ? null : cover,
      title: title,
      subtitle: sub,
      tripForNotes: r,
    );
    if (res == null || !mounted) return;

    // 直接用默认浏览器打开，省掉"去哪个目录找"这一步
    if (Platform.isMacOS) {
      await Process.run('open', [res.indexHtml.path]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', res.indexHtml.path]);
    }
  }

  static String _dateOnly(DateTime? t) {
    if (t == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }

  /// 打开大图。**范围是这一站的全部照片**，不是只有已选的 ——
  /// 挑图时要能一张张看过去，在大图里按空格直接选取。
  void _openViewer(Stop stop, List<PhotoRecord> list, PhotoRecord at) {
    final i = list.indexWhere((e) => e.id == at.id);
    PhotoViewer.open(context,
        c: widget.c, photos: list, index: i < 0 ? 0 : i);
  }

  @override
  Widget build(BuildContext context) {
    final r = route;
    if (r == null || r.isEmpty) return _empty(context);
    return Column(
      children: [
        _toolbar(context, r),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            itemCount: r.stays.length,
            itemBuilder: (context, i) => _stopCard(context, r.stays[i], i),
          ),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          '这个时间范围里没有带 GPS 的照片，没法分站。\n'
          '用上方的时间范围换一段试试。',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.7),
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context, TripRoute r) {
    final scheme = Theme.of(context).colorScheme;
    final totalSelected = r.stays.fold<int>(0, (a, s) => a + _selectedOf(s).length);
    final totalPhotos =
        suggestions.values.fold<int>(0, (a, s) => a + s.totalPhotos);
    final ready = widget.c.signalReadyCount;
    final all = widget.c.photoCount;

    // 工具栏必须能横向滚动。按钮数量是会长的，窗口宽度是用户说了算的，
    // 固定成一行迟早 overflow —— 之前那条黄黑斜线就是这么来的。
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
          Text('${r.stays.length} 站 · ${r.dayCount} 天 · '
              '${r.totalMiles.round()} mi',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 20),
          Text('精选 $totalSelected / $totalPhotos 张',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(width: 20),
          const Text('每站', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          DropdownButton<int>(
            value: targetPerStop,
            underline: const SizedBox.shrink(),
            style: const TextStyle(fontSize: 12),
            items: const [
              DropdownMenuItem(value: 0, child: Text('自动')),
              DropdownMenuItem(value: 3, child: Text('3 张')),
              DropdownMenuItem(value: 5, child: Text('5 张')),
              DropdownMenuItem(value: 8, child: Text('8 张')),
              DropdownMenuItem(value: 12, child: Text('12 张')),
            ],
            onChanged: (v) {
              if (v == null) return;
              targetPerStop = v;
              _recompute();
            },
          ),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: _recompute,
            icon: const Icon(Icons.refresh, size: 15),
            label: const Text('重算建议', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _applyAll,
            icon: const Icon(Icons.auto_awesome, size: 15),
            label: const Text('自动精选全部站', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          widget.c.exporting
              ? Row(children: [
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text('${widget.c.exportDone}/${widget.c.exportTotal}',
                      style: const TextStyle(fontSize: 12)),
                ])
              : FilledButton.icon(
                  onPressed: totalSelected == 0 ? null : _export,
                  icon: const Icon(Icons.ios_share, size: 15),
                  label: const Text('导出 Story 网页',
                      style: TextStyle(fontSize: 12)),
                ),
          const SizedBox(width: 8),
          _fillingCaptions
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : OutlinedButton.icon(
                  onPressed: _fillCaptions,
                  icon: const Icon(Icons.bolt, size: 15),
                  label: const Text('自动生成全部文字',
                      style: TextStyle(fontSize: 12)),
                ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: widget.c.exporting || widget.c.publishing
                ? null
                : () => PublishDialog.show(context, widget.c),
            icon: const Icon(Icons.cloud_upload_outlined, size: 15),
            label: const Text('发布', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          // 片头封面的状态。没选过就是自动挑的那张，明说出来，
          // 别让用户以为"封面是随机的"
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              widget.c.coverPhotoId.isEmpty ? Icons.star_border : Icons.star,
              size: 15,
              color: widget.c.coverPhotoId.isEmpty
                  ? scheme.onSurfaceVariant
                  : const Color(0xFFE0A800),
            ),
            const SizedBox(width: 4),
            Text(
              widget.c.coverPhotoId.isEmpty ? '片头封面：自动' : '片头封面：已指定',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            if (widget.c.coverPhotoId.isNotEmpty)
              TextButton(
                onPressed: () => widget.c.setCoverPhoto(''),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero),
                child: const Text('改回自动', style: TextStyle(fontSize: 11)),
              ),
          ]),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'AI 文案设置',
            onPressed: () => AiSettingsDialog.show(context, widget.c),
            icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
          ),
                ],
              ),
            ),
          ),
          if (ready < all)

            Tooltip(
              message: '还在后台计算去重信号（清晰度、感知哈希、人脸）。\n'
                  '算完之前，去重只能靠拍摄时间兜底，重复照片会偏多。',
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 15),
                  const SizedBox(width: 6),
                  Text('去重信号 $ready / $all',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _stopCard(BuildContext context, Stop stop, int index) {
    final scheme = Theme.of(context).colorScheme;
    final sug = suggestions[stop.seq];
    if (sug == null) return const SizedBox.shrink();
    final all = _photosOf(stop);
    final selected = _selectedOf(stop);
    final expanded = expandedStop == stop.seq;
    final heroId = selected.any((e) => e.id == sug.hero?.id)
        ? sug.hero?.id
        : (selected.isEmpty ? null : selected.first.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('第 ${index + 1} 站',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer)),
                ),
                const SizedBox(width: 10),
                Text(_timeLabel(stop),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                Text(
                  '${stop.lat.toStringAsFixed(3)}, '
                  '${stop.lon.toStringAsFixed(3)}',
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                Text('已选 ${selected.length} / ${all.length} 张',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
                if (sug.duplicatesRemoved > 0) ...[
                  const SizedBox(width: 10),
                  Text('可折叠重复 ${sug.duplicatesRemoved}',
                      style: TextStyle(fontSize: 11, color: scheme.primary)),
                ],
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => _applySuggestion(stop),
                  child: Text('自动精选 ${sug.selected.length} 张',
                      style: const TextStyle(fontSize: 12)),
                ),
                if (selected.isNotEmpty)
                  TextButton(
                    onPressed: () => _clearStop(stop),
                    child: const Text('清空', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // ── 轨道一: 已选进回顾 ──
            _trackLabel(context, '已选进回顾', selected.length, scheme.primary),
            const SizedBox(height: 6),
            _strip(
              context,
              stop,
              selected,
              all,
              size: 92,
              heroId: heroId,
              emptyHint: '这一站还没选照片。点右边的「自动精选」，或在下面挑。',
            ),
            const SizedBox(height: 14),

            // ── 轨道二: 全部照片 ──
            _trackLabel(context, '这一站的全部照片', all.length,
                scheme.onSurfaceVariant),
            const SizedBox(height: 6),
            _strip(
              context,
              stop,
              expanded ? all : all.take(40).toList(),
              all,
              size: 54,
              wrap: expanded,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    setState(() => expandedStop = expanded ? null : stop.seq),
                child: Text(
                    expanded ? '收起' : '展开全部 ${all.length} 张（可换行显示）',
                    style: const TextStyle(fontSize: 12)),
              ),
            ),

            // 这一站的文字。放在最后 —— 先看照片，再写字，顺序是对的。
            StopNoteEditor(
              key: ValueKey('note-${NoteStore.keyFor(stop)}'),
              c: widget.c,
              trip: route!,
              stop: stop,
            ),
          ],
        ),
      ),
    );
  }

  Widget _trackLabel(
      BuildContext context, String text, int count, Color color) {
    return Row(
      children: [
        Container(width: 3, height: 12, color: color),
        const SizedBox(width: 7),
        Text('$text  $count',
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        Text('点图看大图（大图里按空格选取）· 点右上角圆圈直接选取',
            style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }

  /// [photos] 是这一条轨道要显示的，[viewerScope] 是点开大图后能左右翻的范围。
  /// 两条轨道的翻页范围都用**这一站的全部照片** —— 挑图时要能一张张看过去。
  Widget _strip(
    BuildContext context,
    Stop stop,
    List<PhotoRecord> photos,
    List<PhotoRecord> viewerScope, {
    required double size,
    String? heroId,
    bool wrap = false,
    String? emptyHint,
  }) {
    final scheme = Theme.of(context).colorScheme;
    if (photos.isEmpty) {
      return Text(emptyHint ?? '',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant));
    }

    Widget tileFor(PhotoRecord r) {
      return Padding(
        padding: const EdgeInsets.only(right: 6, bottom: 6),
        child: Stack(
          children: [
            PhotoTile(
              record: r,
              file: widget.c.fileOf(r),
              thumbs: widget.c.thumbs!,
              size: size,
              picked: widget.c.isPicked(widget.c.catalog?.byId(r.id) ?? r),
              onTap: () => _openViewer(stop, viewerScope, r),
              onToggleSelect: () => _toggle(r),
            ),
            // 片头封面: 整篇 Story 的第一张，也是分享出去的缩略图。
            // **必须让用户自己指定** —— 自动挑的那张几乎不会是他最想给人看的那张
            Positioned(
              right: 10,
              top: 4,
              child: GestureDetector(
                onTap: () => widget.c.setCoverPhoto(r.id),
                child: Tooltip(
                  message: widget.c.coverPhotoId == r.id
                      ? '这是片头封面'
                      : '设为片头封面',
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      widget.c.coverPhotoId == r.id
                          ? Icons.star
                          : Icons.star_border,
                      size: 15,
                      color: widget.c.coverPhotoId == r.id
                          ? const Color(0xFFFFC94D)
                          : Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
            if (r.id == heroId)
              Positioned(
                left: 4,
                bottom: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('本站首图',
                      style: TextStyle(fontSize: 9, color: Colors.white)),
                ),
              ),
          ],
        ),
      );
    }

    if (wrap) {
      return Wrap(children: photos.map(tileFor).toList());
    }
    return SizedBox(
      height: size + 10,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: photos.map(tileFor).toList(),
      ),
    );
  }

  static String _timeLabel(Stop s) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = '${s.arrive.year}-${two(s.arrive.month)}-${two(s.arrive.day)}';
    final a = '${two(s.arrive.hour)}:${two(s.arrive.minute)}';
    final b = '${two(s.leave.hour)}:${two(s.leave.minute)}';
    return s.duration.inMinutes < 1 ? '$d  $a' : '$d  $a - $b';
  }
}
