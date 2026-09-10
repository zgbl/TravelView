import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

import '../state/photo_source.dart';
import '../state/trips.dart';
import '../ui/theme.dart';
import '../widgets/asset_thumb.dart';
import 'trip_page.dart';

/// 「新建」：从相册里认出一趟趟旅行，挑一趟（或几趟）开始做。
///
/// **相册扫描只发生在这一栏。** 打开 App 只想看看自己发过什么的人
/// （多数时候都是），不该为此等一遍几千张照片的扫描。
///
/// 三个 Tab 对应三种找东西的方式：算法认出来的、按地点、按月份。
/// 智能推荐会漏、会切错，**另外两条路是给它兜底的** ——
/// 只有一条自动的路，用户第一次被切错就再也不信它了。
class NewTripPage extends StatefulWidget {
  const NewTripPage({super.key});

  @override
  State<NewTripPage> createState() => _NewTripPageState();
}

enum _Group { smart, place, month }

class _NewTripPageState extends State<NewTripPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  PermissionState? _perm;
  List<PhotoRecord> _photos = const [];
  List<Trip>? _trips;
  int _done = 0, _total = 0;
  String? _error;
  DateTime? _from, _to;

  /// 多选合并：一次做一篇跨越好几段的回顾。
  /// 十一天的自驾被切成三段是常事，用户想发的是一整趟。
  final Set<int> _merged = {};

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _trips = null;
      _merged.clear();
    });
    try {
      final perm = await PhotoSource.instance.requestPermission();
      if (!mounted) return;
      setState(() => _perm = perm);
      if (!perm.hasAccess) return;

      final photos = await PhotoSource.instance.scan(
        onProgress: (d, t) {
          if (mounted) setState(() { _done = d; _total = t; });
        },
      );
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _trips = detectTrips(photos);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  int get _located => _photos.where((p) => p.hasLocation).length;

  List<Trip> _inRange(List<Trip> list) {
    if (_from == null && _to == null) return list;
    return list.where((t) {
      if (_from != null && t.end.isBefore(_from!)) return false;
      if (_to != null && t.start.isAfter(_to!)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('新建回顾')),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: tr('智能推荐')),
            Tab(text: tr('按地点')),
            Tab(text: tr('按月份')),
          ],
        ),
        actions: [
          IconButton(
            tooltip: tr('重新扫描相册'),
            onPressed: _start,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _SyncBar(
            scanned: _photos.length,
            located: _located,
            scanning: _trips == null && _error == null,
            done: _done,
            total: _total,
            onRefresh: _start,
          ),
          _DateFilter(
            from: _from,
            to: _to,
            onPick: (f, t) => setState(() { _from = f; _to = t; }),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _list(_Group.smart),
                _list(_Group.place),
                _list(_Group.month),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _merged.isEmpty ? null : _mergeBar(),
    );
  }

  Widget _list(_Group group) {
    if (_error != null) {
      return _Hint(
        icon: Icons.error_outline,
        title: tr('读相册时出错了'),
        detail: _error,
        action: FilledButton(onPressed: _start, child: Text(tr('再试一次'))),
      );
    }

    if (_perm != null && !_perm!.hasAccess) {
      return _Hint(
        icon: Icons.photo_library_outlined,
        title: tr('需要访问相册'),
        detail: tr('只读取照片的时间和位置，不会修改或上传你的原件。'),
        action: FilledButton(
          onPressed: PhotoManager.openSetting,
          child: Text(tr('去设置里打开')),
        ),
      );
    }

    final trips = _trips;
    if (trips == null) {
      return _Hint(
        icon: Icons.travel_explore,
        title: tr('正在看你的相册'),
        detail: _total == 0 ? null : trf('{0} / {1} 张', [_done, _total]),
        action: const SizedBox(
            width: 170, child: LinearProgressIndicator()),
      );
    }

    if (trips.isEmpty) {
      final noGps = _photos.isNotEmpty && _located == 0;
      return _Hint(
        icon: noGps ? Icons.location_off_outlined : Icons.map_outlined,
        title: noGps ? tr('照片里读不到位置') : tr('还没找到成形的行程'),
        detail: noGps
            ? tr('在系统设置里给 TravelView 开启相册的完整访问权限'
                '（不要选"仅选中的照片"），然后重新扫描。')
            : trf('看了 {0} 张，其中 {1} 张带位置。', [_photos.length, _located]),
        action: FilledButton(onPressed: _start, child: Text(tr('重新扫描'))),
      );
    }

    final shown = _inRange(trips);
    if (shown.isEmpty) {
      return _Hint(
        icon: Icons.filter_alt_off_outlined,
        title: tr('这个时间段里没有行程'),
        action: TextButton(
          onPressed: () => setState(() { _from = null; _to = null; }),
          child: Text(tr('清除日期筛选')),
        ),
      );
    }

    final sections = _sections(group, shown);

    return ListView(
      padding: const EdgeInsets.fromLTRB(TV.pad, TV.gap, TV.pad, 90),
      children: [
        for (final entry in sections.entries) ...[
          if (sections.length > 1 || group != _Group.smart)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 0, 10),
              child: Text(entry.key,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          for (final t in entry.value)
            Padding(
              padding: const EdgeInsets.only(bottom: TV.gap),
              child: _TripCard(
                trip: t,
                index: trips.indexOf(t),
                selected: _merged.contains(trips.indexOf(t)),
                anySelected: _merged.isNotEmpty,
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => TripPage(t)),
                ),
                onToggle: () => setState(() {
                  final i = trips.indexOf(t);
                  _merged.contains(i) ? _merged.remove(i) : _merged.add(i);
                }),
                onPreview: () => _preview(t),
              ),
            ),
        ],
      ],
    );
  }

  /// 三种分组方式产出的都是"标题 -> 行程"，界面只认这一种形状。
  Map<String, List<Trip>> _sections(_Group g, List<Trip> trips) {
    switch (g) {
      case _Group.smart:
        return {'': trips};

      case _Group.month:
        final out = <String, List<Trip>>{};
        for (final t in trips) {
          out.putIfAbsent('${t.start.year} 年 ${t.start.month} 月', () => [])
              .add(t);
        }
        return out;

      case _Group.place:
        // 没有地名服务，就按"跑了多远"分档 —— 用户脑子里的分类
        // 本来也是"出远门 / 周边 / 市内"，不是精确的行政区划
        final out = <String, List<Trip>>{};
        for (final t in trips) {
          final km = t.spanMeters / 1000;
          final key = km >= 300
              ? tr('远行（300 公里以上）')
              : km >= 50
                  ? tr('周边（50 - 300 公里）')
                  : tr('市内');
          out.putIfAbsent(key, () => []).add(t);
        }
        return out;
    }
  }

  Future<void> _preview(Trip t) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.66,
        builder: (ctx, scroll) => GridView.builder(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
          ),
          itemCount: t.photos.length,
          itemBuilder: (_, i) => ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: AssetThumb(t.photos[i].id),
          ),
        ),
      ),
    );
  }

  Widget _mergeBar() {
    final trips = _trips ?? const <Trip>[];
    final picked = _merged.map((i) => trips[i]).toList();
    final photos = picked.fold<int>(0, (a, t) => a + t.photos.length);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(TV.pad, 10, TV.pad, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          boxShadow: TV.shadow(context),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(trf('已选 {0} 段行程', [picked.length]),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(trf('共 {0} 张照片', [photos]),
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline)),
                ],
              ),
            ),
            FilledButton(
              onPressed: () {
                // 合并成一段：把选中的照片并起来按时间排，
                // 后面的挑图、聚类、成篇完全不用知道它原本是几段
                final all = [for (final t in picked) ...t.photos]
                  ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
                setState(_merged.clear);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => TripPage(Trip(all))),
                );
              },
              child: Text(tr('开始生成回顾')),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部的相册同步状态条。
class _SyncBar extends StatelessWidget {
  final int scanned, located, done, total;
  final bool scanning;
  final VoidCallback onRefresh;

  const _SyncBar({
    required this.scanned,
    required this.located,
    required this.scanning,
    required this.done,
    required this.total,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(TV.pad, 8, 8, 8),
      child: Row(
        children: [
          Icon(scanning ? Icons.sync : Icons.check_circle_outline,
              size: 15,
              color: scanning ? scheme.primary : scheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              scanning
                  ? (total == 0
                      ? tr('正在读相册…')
                      : trf('正在读相册 {0} / {1}', [done, total]))
                  : trf('相册已同步 · {0} 张，其中 {1} 张带位置',
                      [scanned, located]),
              style: TextStyle(fontSize: 11.5, color: scheme.outline),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: scanning ? null : onRefresh,
            style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 10)),
            child: Text(tr('刷新'), style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _DateFilter extends StatelessWidget {
  final DateTime? from, to;
  final void Function(DateTime?, DateTime?) onPick;
  const _DateFilter({required this.from, required this.to, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final active = from != null || to != null;
    String label() {
      String d(DateTime x) => '${x.year}.${x.month}.${x.day}';
      if (!active) return tr('全部时间');
      return '${from == null ? '' : d(from!)} – ${to == null ? '' : d(to!)}';
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(TV.pad, 0, TV.pad, 6),
        child: Wrap(
          spacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.date_range, size: 16),
              label: Text(label(), style: const TextStyle(fontSize: 12)),
              onPressed: () async {
                final now = DateTime.now();
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(now.year - 12),
                  lastDate: now,
                );
                if (range != null) onPick(range.start, range.end);
              },
            ),
            if (active)
              ActionChip(
                label: Text(tr('清除'), style: const TextStyle(fontSize: 12)),
                onPressed: () => onPick(null, null),
              ),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final Trip trip;
  final int index;
  final bool selected;
  final bool anySelected;
  final VoidCallback onOpen;
  final VoidCallback onToggle;
  final VoidCallback onPreview;

  const _TripCard({
    required this.trip,
    required this.index,
    required this.selected,
    required this.anySelected,
    required this.onOpen,
    required this.onToggle,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cover = trip.cover;
    final km = (trip.spanMeters / 1000).round();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TV.rCard),
        boxShadow: TV.shadow(context),
        border: selected
            ? Border.all(color: scheme.primary, width: 2.5)
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TV.rCard),
        child: Material(
          color: Theme.of(context).cardTheme.color,
          child: InkWell(
            // 已经在多选里了，点击就是勾选；否则点击是进去做这一趟
            onTap: anySelected ? onToggle : onOpen,
            onLongPress: onToggle,
            child: Stack(
              children: [
                SizedBox(
                  height: 190,
                  width: double.infinity,
                  child: cover == null
                      ? Container(color: scheme.surfaceContainerHighest)
                      : AssetThumb(cover.id, size: 900),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                      decoration: const BoxDecoration(gradient: TV.scrim)),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _range(trip),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 7),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        _Tag(Icons.calendar_today, trf('{0} 天', [trip.days])),
                        _Tag(Icons.photo_outlined,
                            trf('{0} 张', [trip.photos.length])),
                        if (km > 0)
                          _Tag(Icons.straighten, trf('跨度 {0} 公里', [km])),
                      ]),
                    ],
                  ),
                ),
                // 复选框：批量勾选、合并成一篇
                Positioned(
                  right: 8,
                  top: 8,
                  child: InkWell(
                    onTap: onToggle,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? scheme.primary : Colors.black26,
                          border:
                              Border.all(color: Colors.white, width: 1.8),
                        ),
                        child: selected
                            ? const Icon(Icons.check,
                                size: 16, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
                ),
                // 预览：防误选。缩略图看不出这一段到底是哪次出门
                Positioned(
                  left: 8,
                  top: 8,
                  child: Material(
                    color: Colors.black26,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: onPreview,
                      customBorder: const CircleBorder(),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.visibility_outlined,
                            size: 17, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _range(Trip t) {
    String d(DateTime x) => '${x.year}.${x.month}.${x.day}';
    return t.days <= 1 ? d(t.start) : '${d(t.start)} – ${d(t.end)}';
  }
}

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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(color: Colors.white, fontSize: 11.5)),
        ]),
      );
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? detail;
  final Widget? action;
  const _Hint(
      {required this.icon, required this.title, this.detail, this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 40),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 44, color: scheme.outline),
        const SizedBox(height: 14),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        if (detail != null) ...[
          const SizedBox(height: 8),
          Text(detail!,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline, fontSize: 13, height: 1.5)),
        ],
        if (action != null) ...[
          const SizedBox(height: 20),
          Center(child: action!),
        ],
      ],
    );
  }
}
