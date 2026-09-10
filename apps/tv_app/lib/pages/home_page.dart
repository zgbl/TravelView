import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

import '../state/photo_source.dart';
import '../state/trips.dart';
import '../widgets/asset_thumb.dart';
import 'trip_page.dart';

/// 首屏：**你去过的地方**，一趟一张卡片。
///
/// 桌面端第一屏是"选一个照片库"，手机端不该这样 —— 手机里的相册就是库，
/// 没什么可选的。打开就该看见东西。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  PermissionState? _perm;
  List<Trip>? _trips;
  int _done = 0, _total = 0;
  String? _error;

  /// 扫完之后留着的两个数：一共几张、其中几张带位置。
  ///
  /// **切不出行程时，这两个数就是唯一能说明原因的东西。**
  /// 「一张都没有位置」和「有位置但都在家附近」是完全不同的两个问题，
  /// 前者九成是权限没给对，后者才是阈值的事。
  int _scanned = 0, _located = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _trips = null;
    });
    try {
      final perm = await PhotoSource.instance.requestPermission();
      if (!mounted) return;
      setState(() => _perm = perm);
      // limited 是"只授权了部分照片"，那也能用 —— 当作拒绝会把一大批
      // 选了"仅选中的照片"的用户直接挡在第一屏
      if (!perm.hasAccess) return;

      final photos = await PhotoSource.instance.scan(
        onProgress: (d, t) {
          if (mounted) setState(() { _done = d; _total = t; });
        },
      );
      if (!mounted) return;
      setState(() {
        _scanned = photos.length;
        _located = photos.where((p) => p.hasLocation).length;
        _trips = detectTrips(photos);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TravelView'),
        actions: [
          IconButton(
            tooltip: tr('重新扫描'),
            onPressed: _start,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
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
        detail: tr('TravelView 只读取照片的时间和位置，不会上传任何照片。'),
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
        detail: _total == 0
            ? null
            : trf('{0} / {1} 张', [_done, _total]),
        action: const Padding(
          padding: EdgeInsets.only(top: 20),
          child: SizedBox(
              width: 160, child: LinearProgressIndicator()),
        ),
      );
    }

    if (trips.isEmpty) {
      // 没有一张带位置 —— 几乎一定是权限的问题，不是照片的问题。
      // 这时候讲"没找到行程"是在误导用户去翻自己的相册。
      final noGps = _scanned > 0 && _located == 0;
      return _Hint(
        icon: noGps ? Icons.location_off_outlined : Icons.map_outlined,
        title: noGps ? tr('照片里读不到位置') : tr('还没找到成形的行程'),
        detail: noGps
            ? tr('系统没有把照片的位置信息交给 App。在系统设置里给 TravelView '
                '开启相册的完整访问权限（不要选"仅选中的照片"）之后重新扫描。')
            : trf('看了 {0} 张，其中 {1} 张带位置。相册里连着几天、'
                '又跑得比较远的照片才会被认成一趟旅行。', [_scanned, _located]),
        action: Column(
          children: [
            FilledButton(onPressed: _start, child: Text(tr('重新扫描'))),
            const SizedBox(height: 6),
            TextButton(
              onPressed: PhotoManager.openSetting,
              child: Text(tr('打开系统设置')),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: trips.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) => _TripCard(trips[i]),
    );
  }
}

class _TripCard extends StatelessWidget {
  final Trip trip;
  const _TripCard(this.trip);

  @override
  Widget build(BuildContext context) {
    final cover = trip.cover;
    final scheme = Theme.of(context).colorScheme;
    final km = (trip.spanMeters / 1000).round();

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TripPage(trip)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            SizedBox(
              height: 200,
              width: double.infinity,
              child: cover == null
                  ? Container(color: scheme.surfaceContainerHighest)
                  : AssetThumb(cover.id, size: 800),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _dateRange(trip),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      trf('{0} 天', [trip.days]),
                      trf('{0} 张', [trip.photos.length]),
                      if (km > 0) trf('跨度 {0} 公里', [km]),
                    ].join(' · '),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _dateRange(Trip t) {
    String d(DateTime x) => '${x.year}.${x.month}.${x.day}';
    return t.start.difference(t.end).inDays == 0 && t.days == 1
        ? d(t.start)
        : '${d(t.start)} – ${d(t.end)}';
  }
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: scheme.outline),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(detail!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.outline, fontSize: 13)),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
