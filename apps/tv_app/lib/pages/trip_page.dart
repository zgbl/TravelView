import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

import '../state/selection.dart';
import '../state/trips.dart';
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
  int _tab = 0;

  @override
  void dispose() {
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
          body: _tab == 0
              ? _Timeline(widget.trip, _sel)
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
        onPressed: _sel.isEmpty
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GeneratePage(_sel.picked),
                  ),
                ),
        heroTag: 'go',
        icon: const Icon(Icons.auto_awesome),
        label: Text(_sel.isEmpty
            ? tr('一张都没选')
            : trf('生成回顾 · {0} 张', [_sel.count])),
      );

  String _title() {
    final s = widget.trip.start;
    return '${s.year}.${s.month}.${s.day} · ${trf('{0} 天', [
          widget.trip.days
        ])}';
  }
}

/// 按天分组的照片墙。**分组的是日期，不是"事件"** ——
/// 用户脑子里记的是"第二天去了哪"，不是第 37 个聚类。
class _Timeline extends StatelessWidget {
  final Trip trip;
  final TripSelection sel;
  const _Timeline(this.trip, this.sel);

  @override
  Widget build(BuildContext context) {
    final byDay = <DateTime, List<PhotoRecord>>{};
    for (final p in trip.photos) {
      final d = DateTime(p.takenAt.year, p.takenAt.month, p.takenAt.day);
      byDay.putIfAbsent(d, () => []).add(p);
    }
    final days = byDay.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 90),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        final photos = byDay[day]!;
        final dayPicked = photos.where((p) => sel.has(p.id)).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      trf('第 {0} 天 · {1}月{2}日', [i + 1, day.month, day.day]),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (sel.selecting)
                    TextButton(
                      onPressed: () => sel.toggleDay(photos),
                      child: Text(
                        dayPicked == photos.length
                            ? tr('这天都不要')
                            : trf('这天全要 ({0})', [photos.length]),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
          ],
        );
      },
    );
  }
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
