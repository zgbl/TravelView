import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

import '../state/account.dart';
import '../state/selection.dart';
import '../state/story_draft.dart';
import '../ui/theme.dart';
import '../widgets/asset_thumb.dart';
import 'photo_viewer.dart';
import 'publish_page.dart';

/// 用户从预览页退回行程页时带回去的意图。
///
/// **预览页自己不做第二套编辑器。** 标题、每一站的文字都只有行程页
/// 一个真相；预览页上的每一个"改"最终都翻译成"回到行程页的哪个位置"。
/// 两个地方都能改同一段话，用户会分不清哪个是准的。
class PreviewExit {
  /// 回去以后滚到第几站（null 表示不定位）
  final int? stopSeq;

  /// 回去以后滚到最顶上（改标题）
  final bool toTop;

  /// 回去以后直接进多选状态（增删照片）
  final bool reselect;

  const PreviewExit({this.stopSeq, this.toTop = false, this.reselect = false});
}

/// 生成回顾：把选中的照片聚成一条**有站点的路线**，并且当场给用户看结果。
///
/// 这一步只在手机上算，不联网、不上传、不写文件 —— 用的是 `tv_core` 里
/// 和桌面端同一份聚类算法。
///
/// **它是一个可以回头的检查站，不是一条单行道。** 之前这一页只有一个
/// "发布并分享"：用户看完发现第二站的字写错了，唯一的出路是按系统返回键，
/// 而那看起来像"放弃"。人在这一刻最需要的恰恰是"再改改" ——
/// 一个只能往前的预览页，会逼着用户要么将就发出去，要么整个放弃。
class GeneratePage extends StatefulWidget {
  /// **直接拿选集，不拿快照。** 预览页上划掉一张照片要立刻反映到
  /// 行程页和最终发布的内容里，传一份 List 进来做不到这件事。
  final TripSelection sel;

  /// 用户在行程页上已经写好的标题和每一站的话 —— **接着用，不要重来一份。**
  final StoryDraft draft;

  const GeneratePage({super.key, required this.sel, required this.draft});

  @override
  State<GeneratePage> createState() => _GeneratePageState();
}

class _GeneratePageState extends State<GeneratePage> {
  TripRoute? _route;
  String? _error;

  /// 上一次算路线用的那批照片 id。选集变了才重算 ——
  /// `buildRoute` 是纯计算，但没必要每帧跑一遍。
  String _routeKey = '';

  StoryDraft get draft => widget.draft;
  TripSelection get sel => widget.sel;
  List<PhotoRecord> get photos => sel.picked;

  @override
  void initState() {
    super.initState();
    sel.addListener(_onSelChanged);
    _build();
  }

  @override
  void dispose() {
    sel.removeListener(_onSelChanged);
    super.dispose();
  }

  void _onSelChanged() {
    final key = photos.map((p) => p.id).join(',');
    if (key == _routeKey) return;
    _build();
  }

  Future<void> _build() async {
    final current = photos;
    _routeKey = current.map((p) => p.id).join(',');
    // 让一帧先画出来，否则"正在生成"这一屏根本来不及显示
    await Future<void>.delayed(const Duration(milliseconds: 16));
    try {
      final r = buildRoute(current);
      if (!mounted) return;
      setState(() {
        _route = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// 回行程页，并告诉它回去以后停在哪儿。
  void _back(PreviewExit exit) => Navigator.of(context).pop(exit);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([sel, draft]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(tr('回顾预览')),
          actions: _route == null ? null : _barActions(),
        ),
        body: _body(),
        bottomNavigationBar: _route == null ? null : _bottomBar(),
      ),
    );
  }

  /// 顶部右侧：一个直给的【编辑】，加一个装次要动作的【…】。
  ///
  /// 编辑不藏进菜单 —— 它是这一页上第二常用的动作，藏一层等于没有。
  List<Widget> _barActions() => [
        TextButton.icon(
          onPressed: () => _back(const PreviewExit(toTop: true)),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(tr('编辑')),
        ),
        PopupMenuButton<String>(
          tooltip: tr('更多'),
          onSelected: _onMenu,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'reselect',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_library_outlined, size: 20),
                title: Text(tr('重新选择照片')),
              ),
            ),
            PopupMenuItem(
              value: 'edit',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_note, size: 20),
                title: Text(tr('回去继续编辑')),
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'discard',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline,
                    size: 20, color: Theme.of(context).colorScheme.error),
                title: Text(tr('清空写过的文字'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ),
          ],
        ),
      ];

  Future<void> _onMenu(String v) async {
    switch (v) {
      case 'reselect':
        _back(const PreviewExit(reselect: true));
      case 'edit':
        _back(const PreviewExit(toTop: true));
      case 'discard':
        await _confirmDiscard();
    }
  }

  /// 清空文字是**不可撤销**的，而且清掉的正是这个产品里最花力气的那部分。
  /// 所以必须问一次，而且问句里要说清楚照片不会动 ——
  /// 用户最怕的是"我三百张照片是不是也没了"。
  Future<void> _confirmDiscard() async {
    if (!draft.hasText) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('还没写过文字'))));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('清空写过的文字？')),
        content: Text(
          tr('标题、副标题和每一站写的话都会没有，撤不回来。照片和选择不受影响。'),
          style: const TextStyle(height: 1.6, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr('取消'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('清空')),
          ),
        ],
      ),
    );
    if (ok == true) draft.clearText();
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    final route = _route;
    if (route == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(height: 16),
            Text(trf('正在把 {0} 张照片连成路线…', [photos.length])),
          ],
        ),
      );
    }

    if (route.isEmpty) {
      // **这一屏也要给出路。** 连不成路线时只说一句"回上一页"，
      // 用户还得自己想办法回去。
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('选中的照片里没有带位置的，连不成路线。'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _back(const PreviewExit(reselect: true)),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(tr('回去多选几张')),
              ),
            ],
          ),
        ),
      );
    }

    final all = photos;
    final located = all.where((p) => p.hasLocation).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _Cover(
          coverOf(all),
          route: route,
          photoCount: all.length,
          onPick: () => _openPhoto(all, all.indexOf(coverOf(all))),
        ),
        _HeaderCard(
          draft: draft,
          route: route,
          photoCount: all.length,
          onEdit: () => _back(const PreviewExit(toTop: true)),
        ),
        if (located.length >= 2) _MapStrip(located),
        _TravelModePicker(draft),
        _MusicStatus(draft),
        for (final stop in route.stays)
          _StopCard(
            stop: stop,
            photos: all
                .where((p) => stop.photoIds.contains(p.id))
                .toList(growable: false),
            draft: draft,
            onEdit: () => _back(PreviewExit(stopSeq: stop.seq)),
            onAdd: () => _back(const PreviewExit(reselect: true)),
            onOpen: (photo) => _openPhoto(all, all.indexOf(photo)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(TV.pad, 18, TV.pad, 0),
          child: OutlinedButton.icon(
            onPressed: () => _back(const PreviewExit(reselect: true)),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: Text(tr('添加照片')),
          ),
        ),
      ],
    );
  }

  /// 片头那张。用户没指定就回落到第一张 —— 和 StoryBuilder 里的规则一致。
  PhotoRecord coverOf(List<PhotoRecord> all) {
    final id = draft.coverId;
    if (id != null) {
      for (final p in all) {
        if (p.id == id) return p;
      }
    }
    return all.first;
  }

  /// 点开一张看大图。**带上 draft**，这样放大之后能就地设封面、移出这一篇 ——
  /// 缩略图上看不出谁闭眼了，这两个决定本来就只有在大图上才做得出来。
  void _openPhoto(List<PhotoRecord> all, int index) {
    if (index < 0) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PhotoViewerPage(all, index, sel: sel, draft: draft),
      ),
    );
  }

  /// 底部两颗按钮：左边"再改改"，右边"发出去"。
  ///
  /// **次要动作也要够得着。** 它原来只有一颗发布按钮 —— 一个页面上
  /// 只有一条出路时，用户不会觉得"我可以回去改"，只会觉得"要么发要么算了"。
  Widget _bottomBar() => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => _back(const PreviewExit(toTop: true)),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(tr('回去继续编辑'),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(TV.rControl)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _publish,
                    icon: const Icon(Icons.ios_share),
                    label: Text(tr('发布并分享'),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  /// 没登录就先登录，登录完**直接接着发** —— 不要把用户丢回上一屏
  /// 让他再点一次那个按钮，他刚才已经表达过意图了。
  Future<void> _publish() async {
    final settings = await AppSettings.load();
    final account = Account(settings);

    // 走到这一步一定是登录状态 —— App 开屏就要求登录，
    // 挑完照片写完字才被拦住是最伤人的那种设计
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublishPage(
          photos: photos,
          route: _route!,
          account: account,
          draft: draft,
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final PhotoRecord photo;
  final TripRoute route;
  final int photoCount;
  final VoidCallback onPick;
  const _Cover(this.photo,
      {required this.route, required this.photoCount, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final km = route.totalKm.round();
    final start = route.stays.first.arrive;
    final end = route.stays.last.leave;
    final days = end.difference(start).inDays + 1;

    return GestureDetector(
      onTap: onPick,
      child: Stack(
        children: [
          SizedBox(
              height: 260,
              width: double.infinity,
              child: AssetThumb(photo.id, size: 900)),
          const Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(gradient: TV.scrim)),
          ),
          // 封面是可以换的 —— 但只有一个提示，不占地方
          Positioned(
            right: 12,
            top: 12,
            child: _Pill(
                icon: Icons.auto_awesome_mosaic_outlined,
                label: tr('换封面')),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${start.year}.${start.month}.${start.day}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    trf('{0} 天', [days]),
                    trf('{0} 站', [route.stays.length]),
                    if (km > 0) trf('{0} 公里', [km]),
                    trf('{0} 张', [photoCount]),
                  ].join(' · '),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(TV.rChip),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: Colors.white),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 11.5)),
      ]),
    );
  }
}

/// 标题 + 一句话 + 这一篇的规模。
///
/// **只显示，不就地编辑。** 点一下把人送回行程页顶部去改 ——
/// 同一段话有两个输入框时，用户没办法知道哪个是准的。
class _HeaderCard extends StatelessWidget {
  final StoryDraft draft;
  final TripRoute route;
  final int photoCount;
  final VoidCallback onEdit;
  const _HeaderCard({
    required this.draft,
    required this.route,
    required this.photoCount,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final start = route.stays.first.arrive;
    final end = route.stays.last.leave;
    final hours = end.difference(start).inHours;
    final subtitle = draft.subtitle.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(TV.pad, TV.gap, TV.pad, 0),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(TV.rCard),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        draft.effectiveTitle,
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w700),
                      ),
                      if (subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(subtitle,
                              style:
                                  const TextStyle(fontSize: 13, height: 1.5)),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        [
                          trf('共 {0} 站', [route.stays.length]),
                          trf('{0} 张照片', [photoCount]),
                          if (hours > 0) trf('历时 {0} 小时', [hours]),
                        ].join(' · '),
                        style:
                            TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.edit_outlined, size: 18, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapStrip extends StatelessWidget {
  final List<PhotoRecord> located;
  const _MapStrip(this.located);

  @override
  Widget build(BuildContext context) {
    final pts = located.map((p) => LatLng(p.lat!, p.lon!)).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(TV.pad, TV.gap, TV.pad, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TV.rCard),
        child: SizedBox(
          height: 190,
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.coordinates(
                  coordinates: pts, padding: const EdgeInsets.all(30)),
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.travelview.app',
              ),
              PolylineLayer(polylines: [
                Polyline(
                    points: pts,
                    strokeWidth: 3,
                    color: const Color(0xFF2E6F6A)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一站一张卡片：站号 + 时间 + 【改这一站】+ 照片 + 文字。
///
/// 卡片化不是为了好看 —— 之前几站的文字和照片是连着流下来的，
/// 用户很难一眼看出"这一段属于第三站"。既然每一站都可以单独回去改，
/// 边界就必须画清楚。
class _StopCard extends StatelessWidget {
  final Stop stop;
  final List<PhotoRecord> photos;
  final StoryDraft draft;
  final VoidCallback onEdit;
  final VoidCallback onAdd;
  final void Function(PhotoRecord) onOpen;

  const _StopCard({
    required this.stop,
    required this.photos,
    required this.draft,
    required this.onEdit,
    required this.onAdd,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final a = stop.arrive;
    final name = (draft.stopNames[stop.seq] ?? '').trim();
    final note = (draft.stopNotes[stop.seq] ?? '').trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(TV.pad, TV.gap, TV.pad, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      trf('第 {0} 站 · {1}月{2}日 {3}:{4}', [
                        stop.seq,
                        a.month,
                        a.day,
                        a.hour.toString().padLeft(2, '0'),
                        a.minute.toString().padLeft(2, '0'),
                      ]),
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  // 这一站的入口。图标不带文字会被当成装饰，
                  // 带上"改这一站"四个字才有人点。
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_location_alt_outlined,
                        size: 16),
                    label: Text(tr('改这一站'),
                        style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
              if (name.isEmpty && note.isEmpty)
                // **空状态要说人话。** "这一站还没写字"是描述，
                // 它后面那个可点的动作才是用户要的。
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 2),
                  child: Text(
                    tr('这一站还没写字，点"改这一站"添两句'),
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                ),
              if (name.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 10),
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              if (note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 10),
                  child: Text(note,
                      style: const TextStyle(fontSize: 13, height: 1.5)),
                ),
              const SizedBox(height: 10),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 8),
                  itemCount: photos.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 5),
                  itemBuilder: (_, i) {
                    if (i == photos.length) return _AddTile(onTap: onAdd);
                    final p = photos[i];
                    return _PhotoTile(
                      photo: p,
                      isCover: draft.coverId == p.id,
                      onTap: () => onOpen(p),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final PhotoRecord photo;
  final bool isCover;
  final VoidCallback onTap;
  const _PhotoTile(
      {required this.photo, required this.isCover, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 96,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AssetThumb(photo.id, size: 256),
              if (isCover)
                Positioned(
                  left: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.star,
                        size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 20, color: scheme.outline),
            const SizedBox(height: 3),
            Text(tr('添加'),
                style: TextStyle(fontSize: 11, color: scheme.outline)),
          ],
        ),
      ),
    );
  }
}

/// 这一篇最后会不会有声音。
///
/// **只报状态，不做第二个编辑入口** —— 曲子是在行程页上选的。
/// 但这件事必须在按发布之前看得见：装了曲子却没勾声明的话，
/// 发布出去是一篇哑的，而用户以为自己配好了。
class _MusicStatus extends StatelessWidget {
  final StoryDraft draft;
  const _MusicStatus(this.draft);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = draft.music.length;
    final warn = n > 0 && !draft.musicRightsOk;
    final text = n == 0
        ? tr('没有配乐')
        : (warn
            ? tr('没有勾选声明，发布时不会带上配乐。')
            : trf('配乐 · {0} 首：{1}', [
                n,
                draft.music.map(StoryDraft.trackLabel).join('、'),
              ]));
    return Padding(
      padding: const EdgeInsets.fromLTRB(TV.pad + 2, 12, TV.pad, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(
          warn ? Icons.warning_amber_rounded : Icons.music_note,
          size: 15,
          color: warn ? scheme.error : scheme.outline,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: warn ? scheme.error : scheme.outline)),
        ),
      ]),
    );
  }
}

/// 路线上那个跟着走的标记长什么样。
///
/// **必须让用户选，不能猜。** 算法分不清"市内 30 公里"是开车还是坐地铁，
/// 在城里逛了一天却在路线上开一辆车跑，看的人第一眼就出戏。
/// 默认圆点 —— 不表态永远不会错。
class _TravelModePicker extends StatelessWidget {
  final StoryDraft draft;
  const _TravelModePicker(this.draft);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(TV.pad + 2, 14, TV.pad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('路线上跟着走的标记'),
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final m in kTravelModes)
                ChoiceChip(
                  selected: draft.travelMode == m.id,
                  onSelected: (_) => draft.setTravelMode(m.id),
                  label: Text('${m.emoji} ${tr(m.label)}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
