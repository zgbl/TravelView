import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:tv_core/tv_core.dart';

import '../state/library_controller.dart';
import '../widgets/photo_tile.dart';

/// 行程地图 —— 把一堆散落的照片坐标还原成一条能看的路线。
class MapPage extends StatefulWidget {
  final LibraryController c;
  const MapPage({super.key, required this.c});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final mapController = MapController();
  ClusterOptions options = ClusterOptions.roadTrip;
  TripRoute? route;
  StayPoint? selected;
  DateTimeRange? range;
  bool computing = false;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  Future<void> _recompute() async {
    setState(() => computing = true);
    final all = widget.c.catalog?.photos ?? const <PhotoRecord>[];
    final filtered = range == null
        ? all
        : all.where((p) =>
            p.takenAt.isAfter(range!.start) &&
            p.takenAt.isBefore(range!.end.add(const Duration(days: 1))));
    final r = buildRoute(filtered, options: options);
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

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: range,
    );
    if (r != null) {
      setState(() => range = r);
      await _recompute();
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = route;
    return Column(
      children: [
        _toolbar(context),
        if (computing) const LinearProgressIndicator(),
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
          '这个范围里没有带 GPS 的照片。\n换个日期范围，或者先导入有位置信息的照片。',
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
          OutlinedButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range, size: 16),
            label: Text(_rangeLabel()),
          ),
          if (range != null)
            IconButton(
              tooltip: '清除',
              onPressed: () {
                setState(() => range = null);
                _recompute();
              },
              icon: const Icon(Icons.close, size: 16),
            ),
          const SizedBox(width: 20),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'road', label: Text('长途自驾')),
              ButtonSegment(value: 'city', label: Text('城市游玩')),
            ],
            selected: {
              options.radiusMeters >= 1000 ? 'road' : 'city',
            },
            onSelectionChanged: (s) {
              setState(() => options =
                  s.first == 'road' ? ClusterOptions.roadTrip : ClusterOptions.city);
              _recompute();
            },
          ),
          const Spacer(),
          if (r != null && !r.isEmpty) _summary(context, r),
        ],
      ),
    );
  }

  String _rangeLabel() {
    if (range == null) return '全部照片';
    return '${LibraryLayout.dateStamp(range!.start)} ~ '
        '${LibraryLayout.dateStamp(range!.end)}';
  }

  Widget _summary(BuildContext context, TripRoute r) {
    final scheme = Theme.of(context).colorScheme;
    final items = <String, String>{
      '天数': '${r.dayCount}',
      '地点': '${r.stays.length}',
      '里程': '${r.totalMiles.round()} mi',
      '照片': '${r.stays.fold<int>(0, (a, s) => a + s.photoCount)}',
    };
    return Row(
      children: items.entries
          .map((e) => Padding(
                padding: const EdgeInsets.only(left: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(e.key,
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
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.travelview.desktop',
          maxZoom: 19,
        ),
        PolylineLayer(polylines: _polylines(r)),
        MarkerLayer(markers: _markers(r)),
      ],
    );
  }

  /// 自驾/步行画实线，飞行画虚线（用等距点模拟大圆弧的断续效果）
  List<Polyline> _polylines(TripRoute r) {
    final out = <Polyline>[];
    for (final leg in r.legs) {
      final a = LatLng(leg.from.lat, leg.from.lon);
      final b = LatLng(leg.to.lat, leg.to.lon);
      if (leg.mode == TravelMode.fly) {
        out.add(Polyline(
          points: [a, b],
          color: const Color(0xFF9C6ADE),
          strokeWidth: 2,
          isDotted: true,
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
                ],
              ),
            ),
            ...stays.map((s) => _nodeRow(s)),
          ],
        );
      },
    );
  }

  Widget _nodeRow(StayPoint s) {
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
                    '${LibraryLayout.timeStamp(s.arrive).substring(0, 5)}'
                    '  ${s.lat.toStringAsFixed(3)}, ${s.lon.toStringAsFixed(3)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${s.photoCount} 张 · 停留 ${_dur(s.duration)}',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (widget.c.thumbs != null && s.photoIds.isNotEmpty)
              _cover(s.photoIds.first),
          ],
        ),
      ),
    );
  }

  Widget _cover(String photoId) {
    final rec = widget.c.catalog?.byId(photoId);
    if (rec == null) return const SizedBox.shrink();
    return PhotoTile(
      record: rec,
      file: widget.c.fileOf(rec),
      thumbs: widget.c.thumbs!,
      size: 46,
    );
  }

  static String _dur(Duration d) {
    if (d.inMinutes < 1) return '片刻';
    if (d.inMinutes < 60) return '${d.inMinutes} 分钟';
    if (d.inHours < 24) return '${d.inHours} 小时';
    return '${d.inDays} 天';
  }
}
