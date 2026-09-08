import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tv_core/tv_core.dart';

import '../export/story_exporter.dart';
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

  /// 标题和副标题。**它们是发布出去给读者看的那两行字**，
  /// 和左边那个"工作进度"的名字不是一回事
  late final TextEditingController _title;
  late final TextEditingController _subtitle;
  final _titleFocus = FocusNode();
  final _subtitleFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.c.storyTitle);
    _subtitle = TextEditingController(text: widget.c.storySubtitle);
    widget.c.addListener(_onChanged);
    _recompute();
  }

  @override
  void dispose() {
    widget.c.removeListener(_onChanged);
    _title.dispose();
    _subtitle.dispose();
    _titleFocus.dispose();
    _subtitleFocus.dispose();
    _searchCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get _signature =>
      '${widget.c.rangeStart}|${widget.c.rangeEnd}|${widget.c.photoCount}'
      '|${widget.c.clusterPreset}';

  void _onChanged() {
    // 换了草稿，标题输入框要跟着换 —— 但不能在用户正打字时抢走光标
    if (!_titleFocus.hasFocus && !_subtitleFocus.hasFocus) {
      if (_title.text != widget.c.storyTitle) {
        _title.text = widget.c.storyTitle;
      }
      if (_subtitle.text != widget.c.storySubtitle) {
        _subtitle.text = widget.c.storySubtitle;
      }
    }
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

  /// 生成 Story 网页产物。**发布和"导出看看"共用这一段** ——
  /// 导出和发布之间不可能有别的改动，让用户先点导出再点发布，
  /// 等于把一个实现细节摆到他面前，还多一个"忘了重新导出"的坑。
  ///
  /// 返回 null = 没生成出来（没有行程、一张照片都没选）。
  Future<ExportResult?> _buildExport() async {
    final r = route;
    if (r == null) return null;
    final heroes = <int, String?>{};
    for (final stop in r.stays) {
      final sug = suggestions[stop.seq];
      final selected = _selectedOf(stop);
      if (selected.isEmpty) continue;
      heroes[stop.seq] = selected.any((e) => e.id == sug?.hero?.id)
          ? sug?.hero?.id
          : selected.first.id;
    }

    // 标题优先用用户自己填的那个。**草稿名不是标题** ——
    // 草稿名是给自己找东西用的，标题是读者唯一看得到的那行字
    final title = widget.c.storyTitle.isNotEmpty
        ? widget.c.storyTitle
        : (widget.c.currentProjectName ?? '我的旅行');
    final cover = widget.c.coverPhotoId;
    // **只数真正进 Story 的站。** 副标题写 22 站、统计栏写 7 站，
    // 用户第一眼就会觉得数据是错的 —— 事实上错的是副标题。
    final shownStops =
        r.stays.where((s) => _selectedOf(s).isNotEmpty).length;
    final sub = widget.c.storySubtitle.isNotEmpty
        ? widget.c.storySubtitle
        : '${_dateOnly(r.start)} - ${_dateOnly(r.end)}'
            ' · ${r.dayCount} 天 · $shownStops 站';

    return widget.c.exportStory(
      trip: r,
      heroByStopSeq: heroes,
      coverPhotoId: cover.isEmpty ? null : cover,
      coverMode: widget.c.coverMode,
      units: widget.c.units,
      // **没勾版权声明就不带配乐。** 声明是这条路成立的前提，
      // 不能因为用户忘了勾就默默替他上传
      music: widget.c.musicRightsOk ? widget.c.music : const [],
      title: title,
      subtitle: sub,
      tripForNotes: r,
    );
  }

  /// 导出并在浏览器里打开 —— 发布之前想先自己看一眼时用
  Future<void> _export() async {
    final res = await _buildExport();
    if (res == null || !mounted) return;
    // 直接用默认浏览器打开，省掉"去哪个目录找"这一步
    if (Platform.isMacOS) {
      await Process.run('open', [res.indexHtml.path]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', res.indexHtml.path]);
    }
  }

  /// 发布。**先重新生成一次产物，再打开发布对话框。**
  /// 用户点「发布」想的是"把这篇发出去"，不是"上传我十分钟前导出的那一份" ——
  /// 中间他很可能又改了标题、换了封面、加了配乐。
  Future<void> _publish() async {
    final res = await _buildExport();
    if (res == null || !mounted) return;
    await PublishDialog.show(context, widget.c);
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

  /// 站内查找的关键词。空 = 不过滤。
  String _query = '';
  final _searchCtl = TextEditingController();
  final _searchFocus = FocusNode();

  /// 一站能被搜到的全部文字: 地名、自己写的标题和正文、日期、照片文件名。
  ///
  /// **日期也算文字。** 用户记不住"第 7 站"，但记得"9月8号那天"；
  /// 照片文件名也收进来，是因为从别处拷来的图常常带着有意义的名字。
  String _haystack(Stop stop) {
    final buf = StringBuffer();
    final place = widget.c.placeOf(stop);
    if (place != null) {
      buf.write('${place.names.join(' ')} ${place.landmarks.join(' ')} ');
    }
    final note = widget.c.noteOf(stop);
    // 中英两版都收进来 —— 用户可能用任一种语言想起那一站
    if (note != null) {
      buf.write('${note.title} ${note.note} '
          '${note.titleEn} ${note.noteEn} ');
    }
    buf.write('${_dateOnly(stop.arrive)} ${_dateOnly(stop.leave)} ');
    for (final ph in _photosOf(stop)) {
      buf.write('${ph.origFilename} ');
    }
    return buf.toString().toLowerCase();
  }

  /// 关键词按空格拆开，**每个词都要命中**（AND，不是 OR）。
  /// "新墨西哥 加油" 应该只剩那一站，OR 会把两组结果混在一起，等于没筛。
  List<Stop> _visibleStops(TripRoute r) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return r.stays;
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return r.stays.where((s) {
      final hay = _haystack(s);
      return words.every(hay.contains);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final r = route;
    if (r == null || r.isEmpty) return _empty(context);
    final stops = _visibleStops(r);
    // ⌘F / Ctrl+F 直接跳到查找框 —— 这是所有人手指的肌肉记忆，
    // 让用户满屏找那个小输入框是没道理的
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            () => _searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            () => _searchFocus.requestFocus(),
      },
      child: Focus(
        autofocus: true,
        child: Column(
      children: [
        _toolbar(context, r),
        Expanded(
          child: stops.isEmpty
              ? _noMatch(context)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  itemCount: stops.length,
                  // 序号仍用它在**整条行程里**的真实位置 ——
                  // 筛完重新从 1 数，用户会以为行程被改了
                  itemBuilder: (context, i) =>
                      _stopCard(context, stops[i], r.stays.indexOf(stops[i])),
                ),
        ),
      ],
        ),
      ),
    );
  }

  /// 工具栏那个按钮上的一句话摘要。**要能一眼看出当前是什么设置** ——
  /// 一个只写"呈现"的按钮，用户每次都得点开才知道自己上次选了什么。
  String _lookSummary() {
    final cover = {
      'auto': '自动封面', 'map': '整屏地图', 'mapcard': '地图卡片', 'photo': '照片封面',
    }[widget.c.coverMode] ?? '自动封面';
    final unit = {'auto': '', 'mi': ' · 英里', 'km': ' · 公里'}[widget.c.units] ?? '';
    final music = widget.c.music.isEmpty
        ? ''
        : (widget.c.musicRightsOk
            ? ' · ♪${widget.c.music.length}'
            : ' · ♪(未声明)');
    return '$cover$unit$music';
  }

  /// 「这篇长什么样」的设置。封面、距离单位、配乐 —— 都是发布前定一次
  /// 就不再动的东西，不该长期占着工具栏。
  Future<void> _openLookSettings() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final scheme = Theme.of(ctx).colorScheme;
          void refresh() { setLocal(() {}); setState(() {}); }
          return AlertDialog(
            title: const Text('这篇怎么呈现'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 封面 ──
                  _label('封面'),
                  SegmentedButton<String>(
                    style: const ButtonStyle(
                        visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: 'auto', label: Text('自动')),
                      ButtonSegment(value: 'map', label: Text('整屏地图')),
                      ButtonSegment(value: 'mapcard', label: Text('地图卡片')),
                      ButtonSegment(value: 'photo', label: Text('照片')),
                    ],
                    selected: {widget.c.coverMode},
                    onSelectionChanged: (v) async {
                      await widget.c.setCoverMode(v.first);
                      refresh();
                    },
                  ),
                  if (widget.c.coverMode == 'photo')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        Icon(
                          widget.c.coverPhotoId.isEmpty
                              ? Icons.star_border : Icons.star,
                          size: 15,
                          color: widget.c.coverPhotoId.isEmpty
                              ? scheme.onSurfaceVariant
                              : const Color(0xFFE0A800),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.c.coverPhotoId.isEmpty
                              ? '用自动挑的那张（在照片上点星号可以指定）'
                              : '已指定一张',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                        if (widget.c.coverPhotoId.isNotEmpty)
                          TextButton(
                            onPressed: () async {
                              await widget.c.setCoverPhoto('');
                              refresh();
                            },
                            child: const Text('改回自动',
                                style: TextStyle(fontSize: 12)),
                          ),
                      ]),
                    ),

                  const SizedBox(height: 20),

                  // ── 距离单位 ──
                  _label('距离单位'),
                  SegmentedButton<String>(
                    style: const ButtonStyle(
                        visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: 'auto', label: Text('自动')),
                      ButtonSegment(value: 'mi', label: Text('英里')),
                      ButtonSegment(value: 'km', label: Text('公里')),
                    ],
                    selected: {widget.c.units},
                    onSelectionChanged: (v) async {
                      await widget.c.setUnits(v.first);
                      refresh();
                    },
                  ),
                  if (widget.c.units == 'auto')
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '按每一站所在的国家决定: 美国、英国用英里，其余用公里。'
                        '中英文两个版本用同一个单位。',
                        style: TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            color: scheme.onSurfaceVariant),
                      ),
                    ),

                  const SizedBox(height: 20),

                  // ── 配乐 ──
                  // **我们不提供曲库，用户自己传，最多三首轮流播放。**
                  // 曲库选择永远太少，而且会让我们成为内容的提供方、
                  // 把版权责任揽到自己头上。用户上传，责任在上传者 ——
                  // 所以下面那个声明不是走过场，是这条路成立的前提。
                  _label('配乐（最多 ${LibraryController.maxTracks} 首，轮流播放）'),
                  ...widget.c.music.map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          Icon(
                            LibraryController.isLocalTrack(m)
                                ? Icons.music_note : Icons.link,
                            size: 14, color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(LibraryController.trackLabel(m),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                          ),
                          IconButton(
                            tooltip: '去掉这一首',
                            icon: const Icon(Icons.close, size: 14),
                            constraints:
                                const BoxConstraints(minWidth: 28, minHeight: 28),
                            padding: EdgeInsets.zero,
                            onPressed: () async {
                              await widget.c.removeMusic(m);
                              refresh();
                            },
                          ),
                        ]),
                      )),
                  if (widget.c.music.length < LibraryController.maxTracks)
                    Row(children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await _pickMusicFile();
                          refresh();
                        },
                        icon: const Icon(Icons.audio_file_outlined, size: 15),
                        label: Text(
                          widget.c.music.isEmpty ? '选一个音频文件…' : '再加一首',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          await _askMusicUrl();
                          refresh();
                        },
                        child: const Text('用外部链接',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ]),
                  if (widget.c.music.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    // 版权声明。**增删任何一首都要重新勾** ——
                    // 一次勾选管到永远，等于没有声明
                    CheckboxListTile(
                      value: widget.c.musicRightsOk,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) async {
                        await widget.c.setMusicRights(v ?? false);
                        refresh();
                      },
                      title: const Text(
                        '这些音乐我拥有使用权，或它们允许商用/公开分享，'
                        '由此产生的版权责任由我承担。',
                        style: TextStyle(fontSize: 12, height: 1.5),
                      ),
                    ),
                    Text(
                      '本地文件会随游记一起上传，删掉这篇游记时一并删除；'
                      '外部链接的文件不在我们这儿，对方一旦失效就没声音了。',
                      style: TextStyle(
                          fontSize: 11, height: 1.5,
                          color: scheme.onSurfaceVariant),
                    ),
                    if (!widget.c.musicRightsOk)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('没有勾选声明，发布时不会带上配乐。',
                            style:
                                TextStyle(fontSize: 11, color: scheme.error)),
                      ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '只在全屏播放时出声，默认静音，读者点一下才播。',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('好')),
            ],
          );
        },
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );

  /// 从本地选一个音频文件。
  ///
  /// **不复制到别处，只记路径。** 真正的拷贝发生在导出那一刻 ——
  /// 用户可能选完又换、又去掉，提前拷贝只会在库里堆垃圾。
  Future<void> _pickMusicFile() async {
    const group = XTypeGroup(
      label: '音频',
      extensions: ['mp3', 'm4a', 'aac', 'ogg', 'wav'],
    );
    final f = await openFile(acceptedTypeGroups: const [group]);
    if (f == null) return;
    final size = await File(f.path).length();
    // 20MB 以上多半是整张专辑或者无损文件。一篇游记的读者要先下完
    // 才有声音，太大等于没有
    if (size > 10 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('这个文件 ${(size / 1024 / 1024).round()}MB，'
            '超过了服务器 10MB 的单文件上限。'
            '配乐几 MB 就够 —— 读者要下完才有声音。'),
        duration: const Duration(seconds: 5),
      ));
      return;
    }
    await widget.c.addMusic(f.path);   // 加了曲子，版权声明重新来
  }

  /// 让用户贴一个音频直链。
  ///
  /// **只收 https 的音频文件直链，不收网页地址。**
  /// 用户很容易把 Pixabay 的页面地址贴进来 —— 那是一个 HTML 页面，
  /// 播放器拿到它只会静静地不出声，而用户会以为是我们坏了。
  Future<void> _askMusicUrl() async {
    // 空着开始 —— 现在是"再加一首"，预填上一首的地址只会让人误改
    final ctl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('用一个外部链接作为配乐'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'https://…/song.mp3',
              helperText: '必须是 https 的音频文件直链（.mp3 / .m4a / .ogg），\n'
                  '不是播放页面的网址',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '音乐存在对方服务器上，我们不复制也不保存。\n'
            '好处是版权关系清楚；代价是对方一旦防盗链、改地址或删文件，\n'
            '这篇游记就永久没有声音了，而且你不会收到任何通知。\n'
            '要稳定，建议用上面曲库里的曲子。',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(''),
              child: const Text('不用配乐')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
              child: const Text('用这个')),
        ],
      ),
    );
    if (url == null) return;                     // 取消: 什么都不改
    if (url.isEmpty) return;
    if (!url.startsWith('https://')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('只能用 https 开头的链接 —— http 会被浏览器整页拦掉'),
      ));
      return;
    }
    await widget.c.addMusic(url);
  }

  Widget _noMatch(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('没有哪一站包含「$_query」',
            style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() {
            _query = '';
            _searchCtl.clear();
          }),
          child: const Text('清除查找'),
        ),
      ]),
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
    final totalSelected =
        r.stays.fold<int>(0, (a, s) => a + _selectedOf(s).length);
    final totalPhotos =
        suggestions.values.fold<int>(0, (a, s) => a + s.totalPhotos);
    final ready = widget.c.signalReadyCount;
    final all = widget.c.photoCount;

    // **两排，不是一排。** 按钮只会越来越多，挤在一行里迟早溢出，
    // 而且"设置"和"动作"混在一起，用户每次都得从头扫一遍。
    //   第一排 = 这篇东西是什么（标题、副标题、统计）
    //   第二排 = 拿它做什么（精选、导出、发布）+ 怎么呈现（封面）
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 第一排: 标题 ──
          Row(children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _title,
                focusNode: _titleFocus,
                onChanged: (v) => widget.c.setStoryTitle(v),
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: widget.c.currentProjectName ?? '给这篇起个标题',
                  hintStyle: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: scheme.outline),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _subtitle,
                focusNode: _subtitleFocus,
                onChanged: (v) =>
                    widget.c.setStoryTitle(_title.text, subtitle: v),
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '${_dateOnly(r.start)} - ${_dateOnly(r.end)}'
                      ' · ${r.dayCount} 天 · ${r.stays.length} 站',
                  hintStyle:
                      TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 200,
              child: TextField(
                controller: _searchCtl,
                focusNode: _searchFocus,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 16),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 14),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 26, minHeight: 26),
                          onPressed: () => setState(() {
                            _query = '';
                            _searchCtl.clear();
                          }),
                        ),
                  hintText: '查找地点、文字、日期',
                  hintStyle: TextStyle(fontSize: 12, color: scheme.outline),
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text('${r.stays.length} 站 · ${r.dayCount} 天 · '
                '${r.totalMiles.round()} mi · 精选 $totalSelected/$totalPhotos',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            if (ready < all) ...[
              const SizedBox(width: 12),
              Tooltip(
                message: '还在后台计算去重信号（清晰度、感知哈希、人脸）。\n'
                    '算完之前，去重只能靠拍摄时间兜底，重复照片会偏多。',
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.info_outline, size: 14),
                  const SizedBox(width: 4),
                  Text('$ready/$all',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ]),
              ),
            ],
          ]),

          const SizedBox(height: 10),

          // ── 第二排: 动作 + 呈现 ──
          // 仍然可横向滚动兜底，但正常窗口宽度下不需要滚
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
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
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed: _recompute,
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('重算建议', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _applyAll,
                icon: const Icon(Icons.auto_awesome, size: 15),
                label:
                    const Text('自动精选全部站', style: TextStyle(fontSize: 12)),
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
              IconButton(
                tooltip: 'AI 文案设置',
                onPressed: () => AiSettingsDialog.show(context, widget.c),
                icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
              ),

              _sep(scheme),

              // **呈现设置收进一个对话框。**
              // 封面、距离单位、配乐都是"这篇长什么样"，不是"现在要做什么"。
              // 它们平时不用改，却一直占着工具栏最贵的横向空间 ——
              // 而这一行还要继续加东西，塞到最后就是谁也看不清。
              OutlinedButton.icon(
                onPressed: _openLookSettings,
                icon: const Icon(Icons.tune, size: 15),
                label: Text(_lookSummary(),
                    style: const TextStyle(fontSize: 12)),
              ),

              _sep(scheme),

              // 交付动作放最后、也最重
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
                  : OutlinedButton.icon(
                      onPressed: totalSelected == 0 ? null : _export,
                      icon: const Icon(Icons.ios_share, size: 15),
                      label: const Text('导出网页',
                          style: TextStyle(fontSize: 12)),
                    ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: widget.c.exporting || widget.c.publishing
                    ? null
                    : _publish,
                icon: const Icon(Icons.cloud_upload_outlined, size: 15),
                label: const Text('发布', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  /// 两组之间的竖线。视觉上把"处理照片"和"怎么呈现"分开
  Widget _sep(ColorScheme scheme) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(width: 1, height: 20, color: scheme.outlineVariant),
      );

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
            // 只在"片头用照片"时才需要这颗星
            if (widget.c.coverMode == 'photo')
            Positioned(
              right: 10,
              top: 4,
              child: GestureDetector(
                onTap: () => widget.c.setCoverPhoto(r.id),
                child: Tooltip(
                  message: widget.c.coverPhotoId == r.id
                      ? '这是封面照片'
                      : '设为封面照片',
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
