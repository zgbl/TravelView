import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

import '../state/selection.dart';
import '../state/story_draft.dart';
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
          // 输入法弹出来时要把正在写的那一行顶上去，不能盖住
          resizeToAvoidBottomInset: true,
          body: _tab == 0
              ? _Timeline(widget.trip, _route, _sel, _draft)
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
                    builder: (_) => GeneratePage(_sel.picked, draft: _draft),
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
  const _Timeline(this.trip, this.route, this.sel, this.draft);

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
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: 1 + stops.length + (orphans.isEmpty ? 0 : 1),
      itemBuilder: (context, index) {
        if (index == 0) return _TitleBlock(draft);

        final i = index - 1;
        if (i < stops.length) {
          final stop = stops[i];
          final photos = stop.photoIds
              .map((id) => byId[id])
              .whereType<PhotoRecord>()
              .toList();
          return _StopSection(
            stop: stop,
            index: i,
            photos: photos,
            trip: trip,
            sel: sel,
            draft: draft,
          );
        }

        return _StopSection(
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
