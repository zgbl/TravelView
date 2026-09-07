import 'dart:math' as math;

import 'route.dart';

/// 一个坐标点。存进 manifest 时用 GeoJSON 的 [lon, lat] 顺序。
class LatLon {
  final double lat;
  final double lon;
  const LatLon(this.lat, this.lon);

  /// GeoJSON 是 [经度, 纬度]，和习惯的写法相反，这里统一在一个地方处理
  List<double> toGeoJson() => [lon, lat];
  factory LatLon.fromGeoJson(List<dynamic> c) =>
      LatLon((c[1] as num).toDouble(), (c[0] as num).toDouble());
}

enum TravelMode2 { driving, walking, direct, flight }

/// 这条路线是怎么来的 —— **必须如实告诉用户**。
///
/// 我们只知道两个端点，不知道用户当时是不是绕了风景道。
/// 说成"这就是你走过的路"是在骗人。
enum RouteSource {
  /// 由路径规划推算出的最可能走法
  inferred,

  /// 由密集的照片 GPS 点匹配到道路网络还原出来的
  reconstructed,

  /// 真实轨迹（将来接入 GPX / 手机轨迹时才会有）
  actual,
}

/// 一段路线。这是 Story manifest 里的持久数据 ——
/// **算一次，永久存**，网页打开时不再需要任何 API。
class RouteLeg {
  final String fromStopId;
  final String toStopId;
  final TravelMode2 mode;
  final RouteSource source;
  final String provider;
  final List<LatLon> geometry;
  final double distanceMeters;
  final Duration? duration;

  /// 这一段主要走了哪几条路，按里程排序，例如 ['I 40', 'US 285']。
  /// **给文案用的**: "从阿尔伯克基开过来"和"沿 40 号州际公路开过来"
  /// 是两句话，后者才像一个真的走过这条路的人写的。
  final List<String> roads;

  const RouteLeg({
    required this.fromStopId,
    required this.toStopId,
    required this.mode,
    required this.source,
    required this.provider,
    required this.geometry,
    required this.distanceMeters,
    this.duration,
    this.roads = const [],
  });

  Map<String, dynamic> toJson() => {
        'from': fromStopId,
        'to': toStopId,
        'mode': mode.name,
        'source': source.name,
        if (roads.isNotEmpty) 'roads': roads,
        'provider': provider,
        'distanceMeters': distanceMeters,
        if (duration != null) 'durationSeconds': duration!.inSeconds,
        'geometry': {
          'type': 'LineString',
          'coordinates': geometry.map((e) => e.toGeoJson()).toList(),
        },
      };

  factory RouteLeg.fromJson(Map<String, dynamic> j) => RouteLeg(
        fromStopId: j['from'] as String,
        toStopId: j['to'] as String,
        mode: TravelMode2.values.firstWhere((e) => e.name == j['mode'],
            orElse: () => TravelMode2.direct),
        source: RouteSource.values.firstWhere((e) => e.name == j['source'],
            orElse: () => RouteSource.inferred),
        provider: j['provider'] as String? ?? 'direct',
        distanceMeters: (j['distanceMeters'] as num?)?.toDouble() ?? 0,
        duration: j['durationSeconds'] == null
            ? null
            : Duration(seconds: (j['durationSeconds'] as num).toInt()),
        geometry: ((j['geometry'] as Map)['coordinates'] as List)
            .map((c) => LatLon.fromGeoJson(c as List))
            .toList(),
      );
}

/// 路径规划的统一接口。
///
/// 换供应商不该动上层代码 —— 也不该让用户知道我们用的是谁。
/// 界面上只有「驾车 / 步行 / 直线」，后面是哪家是我们的事。
abstract class RouteProvider {
  String get name;
  Future<RouteLeg?> route({
    required String fromStopId,
    required String toStopId,
    required LatLon from,
    required LatLon to,
    required TravelMode2 mode,
  });
}

/// 直线。永远可用、不联网、不依赖任何服务 ——
/// 所有联网供应商失败时都退回它，保证行程图**任何情况下都画得出来**。
class DirectRouteProvider implements RouteProvider {
  const DirectRouteProvider();

  @override
  String get name => 'direct';

  @override
  Future<RouteLeg?> route({
    required String fromStopId,
    required String toStopId,
    required LatLon from,
    required LatLon to,
    required TravelMode2 mode,
  }) async {
    return RouteLeg(
      fromStopId: fromStopId,
      toStopId: toStopId,
      mode: TravelMode2.direct,
      source: RouteSource.inferred,
      provider: name,
      geometry: [from, to],
      distanceMeters: haversineMeters(from.lat, from.lon, to.lat, to.lon),
    );
  }
}

/// 折线的几何计算。小车动画、进度条、路线"长出来"全靠这些。
///
/// 名字不叫 Polyline 是为了避开 flutter_map 的同名组件 ——
/// 那是地图上的绘制对象，这里是纯几何数据，两者不该混。
class RoutePath {
  final List<LatLon> points;

  /// 每个点的累计距离，长度与 points 相同，首项为 0
  final List<double> cumulative;

  RoutePath(this.points) : cumulative = _cumulative(points);

  double get totalMeters => cumulative.isEmpty ? 0 : cumulative.last;

  static List<double> _cumulative(List<LatLon> pts) {
    final out = <double>[];
    var acc = 0.0;
    for (var i = 0; i < pts.length; i++) {
      if (i > 0) {
        acc += haversineMeters(
            pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon);
      }
      out.add(acc);
    }
    return out;
  }

  /// 沿路线走到 [progress]（0..1）时的位置。小车就画在这里。
  LatLon? positionAt(double progress) {
    if (points.isEmpty) return null;
    if (points.length == 1) return points.first;
    final target = totalMeters * progress.clamp(0.0, 1.0);
    final i = _segmentAt(target);
    final segStart = cumulative[i];
    final segLen = cumulative[i + 1] - segStart;
    final t = segLen <= 0 ? 0.0 : (target - segStart) / segLen;
    return LatLon(
      points[i].lat + (points[i + 1].lat - points[i].lat) * t,
      points[i].lon + (points[i + 1].lon - points[i].lon) * t,
    );
  }

  /// 该位置的前进方向（度，正北为 0）。车头朝向靠它，转弯时车也会转。
  double bearingAt(double progress) {
    if (points.length < 2) return 0;
    final target = totalMeters * progress.clamp(0.0, 1.0);
    final i = _segmentAt(target);
    return bearing(points[i], points[i + 1]);
  }

  /// 已经走过的那一段。路线"随滚动逐渐长出来"用这个。
  List<LatLon> traveled(double progress) {
    if (points.isEmpty) return const [];
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return [points.first];
    if (p >= 1) return List.of(points);
    final target = totalMeters * p;
    final i = _segmentAt(target);
    final head = points.sublist(0, i + 1);
    final tip = positionAt(p);
    return tip == null ? head : [...head, tip];
  }

  int _segmentAt(double targetMeters) {
    var lo = 0, hi = points.length - 2;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (cumulative[mid + 1] < targetMeters) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static double bearing(LatLon a, LatLon b) {
    final lat1 = a.lat * math.pi / 180;
    final lat2 = b.lat * math.pi / 180;
    final dLon = (b.lon - a.lon) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final deg = math.atan2(y, x) * 180 / math.pi;
    return (deg + 360) % 360;
  }

  /// 抽稀（Douglas-Peucker）。
  ///
  /// **这一步是必须的**: 横穿美国的一段路线可能有上万个点，
  /// 原样存进 manifest 会让分享页的 JSON 变成好几 MB，手机上打开会很慢。
  /// 容差 10 米在洲际尺度上肉眼看不出差别。
  static List<LatLon> simplify(List<LatLon> pts, {double toleranceMeters = 10}) {
    if (pts.length <= 2) return List.of(pts);
    final keep = List<bool>.filled(pts.length, false);
    keep[0] = true;
    keep[pts.length - 1] = true;
    _dp(pts, 0, pts.length - 1, toleranceMeters, keep);
    final out = <LatLon>[];
    for (var i = 0; i < pts.length; i++) {
      if (keep[i]) out.add(pts[i]);
    }
    return out;
  }

  static void _dp(List<LatLon> pts, int first, int last, double tol,
      List<bool> keep) {
    if (last <= first + 1) return;
    var maxDist = 0.0;
    var index = first;
    for (var i = first + 1; i < last; i++) {
      final d = _perpendicularMeters(pts[i], pts[first], pts[last]);
      if (d > maxDist) {
        maxDist = d;
        index = i;
      }
    }
    if (maxDist > tol) {
      keep[index] = true;
      _dp(pts, first, index, tol, keep);
      _dp(pts, index, last, tol, keep);
    }
  }

  static double _perpendicularMeters(LatLon p, LatLon a, LatLon b) {
    // 小范围内按平面近似即可，误差远小于容差
    final scale = math.cos(a.lat * math.pi / 180);
    final ax = a.lon * scale, ay = a.lat;
    final bx = b.lon * scale, by = b.lat;
    final px = p.lon * scale, py = p.lat;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return haversineMeters(p.lat, p.lon, a.lat, a.lon);
    var t = ((px - ax) * dx + (py - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = ax + dx * t, cy = ay + dy * t;
    return haversineMeters(py, px / scale, cy, cx / scale);
  }
}
