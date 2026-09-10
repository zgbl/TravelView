import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:tv_core/tv_core.dart';

import 'package:tv_shared/tv_shared.dart';
import '../state/library_controller.dart';
import '../widgets/photo_tile.dart';
import '../widgets/route_settings_dialog.dart';
import 'photo_viewer.dart';

/// 行程地图 —— 把一堆散落的照片坐标还原成一条能看的路线。
class MapPage extends StatefulWidget {
  final LibraryController c;
  const MapPage({super.key, required this.c});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final mapController = MapController();
  ClusterOptions get options => widget.c.clusterPreset == 'city'
      ? ClusterOptions.city
      : ClusterOptions.roadTrip;
  TripRoute? route;
  Stop? selected;
  bool computing = false;
  String _lastSignature = '';

  @override
  void initState() {
    super.initState();
    widget.c.addListener(_onLibraryChanged);
    _recompute();
  }

  @override
  void dispose() {
    widget.c.removeListener(_onLibraryChanged);
    super.dispose();
  }

  /// 全局时间范围一变，地图立刻重算 —— 这是"随时换一段行程来看"的关键
  String get _signature =>
      '${widget.c.rangeStart}|${widget.c.rangeEnd}|${widget.c.photoCount}'
      '|${widget.c.clusterPreset}';

  void _onLibraryChanged() {
    if (_signature != _lastSignature) _recompute();
  }

  Future<void> _recompute() async {
    _lastSignature = _signature;
    setState(() => computing = true);
    // 用全局范围筛过的照片，和照片视图看到的是同一批
    final r = buildRoute(widget.c.visiblePhotos, options: options);
    setState(() {
      route = r;
      selected = null;
      computing = false;
    });
    if (r.stays.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds(r));
    }
  }

  void _fitBounds(TripRoute r) {
    final pts = r.stays.map((s) => LatLng(s.lat, s.lon)).toList();
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      mapController.move(pts.first, 11);
      return;
    }
    mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(56),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = route;
    return Column(
      children: [
        _toolbar(context),
        if (computing || widget.c.routing) const LinearProgressIndicator(),
        if (widget.c.routeError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.c.routeError!,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onErrorContainer),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      RouteSettingsDialog.show(context, widget.c),
                  child: Text(tr('去设置'), style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        Expanded(
          child: r == null || r.isEmpty
              ? _empty(context)
              : Row(
                  children: [
                    Expanded(flex: 3, child: _map(r)),
                    const VerticalDivider(width: 1),
                    SizedBox(width: 300, child: _nodeList(r)),
                  ],
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
          tr('这个时间范围里没有带 GPS 的照片。\n'
              '用上方的日期范围换一段，或者先导入有位置信息的照片。'),
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.7),
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = route;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          // 窗口变窄时这一排放不下，让它自己横向滚动
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'road', label: Text(tr('长途自驾'))),
              ButtonSegment(value: 'city', label: Text(tr('城市游玩'))),
            ],
            selected: {widget.c.clusterPreset},
            onSelectionChanged: (s) => widget.c.setClusterPreset(s.first),
          ),
          const SizedBox(width: 20),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'driving', label: Text(tr('驾车'))),
              ButtonSegment(value: 'walking', label: Text(tr('步行'))),
              ButtonSegment(value: 'direct', label: Text(tr('直线'))),
            ],
            selected: {widget.c.routeMode},
            onSelectionChanged: (s) => widget.c.routeMode = s.first,
          ),
          const SizedBox(width: 10),
          if (widget.c.routeMode != 'direct')
            widget.c.routing
                ? Row(
                    children: [
                      const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Text('${widget.c.routeDone}/${widget.c.routeTotal}',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  )
                : FilledButton.tonalIcon(
                    onPressed: r == null || r.isEmpty
                        ? null
                        : () => widget.c.computeRoads(r),
                    icon: const Icon(Icons.alt_route, size: 15),
                    label: Text(
                        widget.c.roadLegs.isEmpty ? tr('贴合道路') : tr('重算路线'),
                        style: const TextStyle(fontSize: 12)),
                  ),
          IconButton(
            tooltip: tr('道路路线服务设置'),
            onPressed: () => RouteSettingsDialog.show(context, widget.c),
            icon: const Icon(Icons.settings_outlined, size: 18),
          ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (r != null && !r.isEmpty) _summary(context, r),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context, TripRoute r) {
    final scheme = Theme.of(context).colorScheme;
    final roads = widget.c.roadLegs;
    final roadMiles = roads.isEmpty
        ? null
        : roads.fold<double>(0, (a, l) => a + l.distanceMeters) / 1609.344;
    final items = <String, String>{
      '天数': '${r.dayCount}',
      '站': '${r.stays.length}',
      // 有道路路线时用道路里程 —— 直线里程总会明显偏小
      '里程': roadMiles == null
          ? trf('{0} mi 直线', [r.totalMiles.round()])
          : trf('{0} mi 道路', [roadMiles.round()]),
      '照片': '${r.stays.fold<int>(0, (a, s) => a + s.photoCount)}',
    };
    return Row(
      children: items.entries
          .map((e) => Padding(
                padding: const EdgeInsets.only(left: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(tr(e.key),
                        style: TextStyle(
                            fontSize: 10, color: scheme.onSurfaceVariant)),
                    Text(e.value,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _map(TripRoute r) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: LatLng(r.stays.first.lat, r.stays.first.lon),
        initialZoom: 4,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        // 开发期用 OSM 官方瓦片。它明确只允许轻量/开发用途，
        // 上线前必须换成自托管（见 Design/map-tiles.md）。
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.travelview.desktop',
          maxZoom: 19,
        ),
        PolylineLayer(polylines: _polylines(r)),
        MarkerLayer(markers: _markers(r)),
        // ODbL 许可强制要求署名，不是可选项
        const SimpleAttributionWidget(
          source: Text('© OpenStreetMap contributors'),
        ),
      ],
    );
  }

  /// 有算好的道路路线就画道路，否则退回站与站之间的直线。
  List<Polyline> _polylines(TripRoute r) {
    final roads = widget.c.roadLegs;
    if (roads.isNotEmpty) {
      return roads.map((leg) {
        final pts = leg.geometry
            .map((e) => LatLng(e.lat, e.lon))
            .toList(growable: false);
        final isFlight = leg.mode == TravelMode2.flight;
        return Polyline(
          points: pts,
          color: isFlight
              ? const Color(0xFF9C6ADE)
              : (leg.provider == 'direct'
                  // 退回直线的段用浅色区分，一眼看出哪几段没取到道路
                  ? const Color(0xFF9AA6A5)
                  : const Color(0xFF2E6F6A)),
          strokeWidth: isFlight ? 2 : 3.4,
          pattern: isFlight ? StrokePattern.dotted() : const StrokePattern.solid(),
        );
      }).toList();
    }

    final out = <Polyline>[];
    for (final leg in r.legs) {
      final a = LatLng(leg.from.lat, leg.from.lon);
      final b = LatLng(leg.to.lat, leg.to.lon);
      if (leg.mode == TravelMode.fly) {
        out.add(Polyline(
          points: [a, b],
          color: const Color(0xFF9C6ADE),
          strokeWidth: 2,
          // flutter_map 7.0 起 isDotted 被 pattern 取代
          pattern: StrokePattern.dotted(),
        ));
      } else {
        out.add(Polyline(
          points: [a, b],
          color: const Color(0xFF2E6F6A),
          strokeWidth: leg.mode == TravelMode.walk ? 2 : 3.2,
        ));
      }
    }
    return out;
  }

  List<Marker> _markers(TripRoute r) {
    final maxCount = r.stays.fold<int>(1, (a, s) => math.max(a, s.photoCount));
    return r.stays.map((s) {
      final t = s.photoCount / maxCount;
      final size = 18.0 + 22.0 * math.sqrt(t);
      final isSel = selected?.seq == s.seq;
      return Marker(
        point: LatLng(s.lat, s.lon),
        width: size + 8,
        height: size + 8,
        child: GestureDetector(
          onTap: () {
            setState(() => selected = s);
            mapController.move(LatLng(s.lat, s.lon), 11);
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSel
                  ? const Color(0xFFE8743B)
                  : const Color(0xFF2E6F6A).withValues(alpha: 0.85),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              '${s.photoCount}',
              style: TextStyle(
                color: Colors.white,
                fontSize: size < 26 ? 9 : 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _nodeList(TripRoute r) {
    final scheme = Theme.of(context).colorScheme;
    final days = r.byDay.keys.toList()..sort();
    return ListView.builder(
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        final stays = r.byDay[day]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              color: scheme.surfaceContainerLow,
              child: Row(
                children: [
                  Text('Day ${i + 1}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text(day,
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                  const Spacer(),
                  Text(
                    '${LibraryLayout.timeStamp(stays.first.arrive).substring(0, 5)}'
                    ' - '
                    '${LibraryLayout.timeStamp(stays.last.leave).substring(0, 5)}',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 14),
                ],
              ),
            ),
            ...stays.map((s) => _nodeRow(s)),
          ],
        );
      },
    );
  }

  Widget _nodeRow(Stop s) {
    final scheme = Theme.of(context).colorScheme;
    final isSel = selected?.seq == s.seq;
    return InkWell(
      onTap: () {
        setState(() => selected = s);
        mapController.move(LatLng(s.lat, s.lon), 11);
      },
      child: Container(
        color: isSel ? scheme.primaryContainer.withValues(alpha: 0.4) : null,
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _timeSpan(s),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${s.lat.toStringAsFixed(4)}, ${s.lon.toStringAsFixed(4)}',
                    style: TextStyle(
                        fontSize: 10.5, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    trf('{0} 张 · 停留 {1}', [s.photoCount, _dur(s.duration)]),
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (widget.c.thumbs != null && s.photoIds.isNotEmpty) _cover(s),
          ],
        ),
      ),
    );
  }

  Widget _cover(Stop stay) {
    final cat = widget.c.catalog;
    if (cat == null) return const SizedBox.shrink();
    final rec = cat.byId(stay.photoIds.first);
    if (rec == null) return const SizedBox.shrink();
    return PhotoTile(
      record: rec,
      file: widget.c.fileOf(rec),
      thumbs: widget.c.thumbs!,
      size: 46,
      onTap: () {
        // 翻页范围就是这个地点的照片
        final photos = stay.photoIds
            .map(cat.byId)
            .whereType<PhotoRecord>()
            .toList()
          ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
        if (photos.isEmpty) return;
        PhotoViewer.open(context, c: widget.c, photos: photos, index: 0);
      },
    );
  }

  /// 到达 - 离开，精确到分钟。只有一张照片时就只显示一个时刻。
  static String _timeSpan(Stop s) {
    final a = LibraryLayout.timeStamp(s.arrive).substring(0, 5);
    if (s.duration.inMinutes < 1) return a;
    final b = LibraryLayout.timeStamp(s.leave).substring(0, 5);
    return '$a - $b';
  }

  static String _dur(Duration d) {
    if (d.inMinutes < 1) return tr('片刻');
    if (d.inMinutes < 60) return trf('{0} 分钟', [d.inMinutes]);
    if (d.inHours < 24) return trf('{0} 小时', [d.inHours]);
    return trf('{0} 天', [d.inDays]);
  }
}
