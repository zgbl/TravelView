import 'dart:math' as math;

import 'models.dart';

/// 两点间大圆距离（米）
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371008.8; // 地球平均半径
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _rad(double deg) => deg * math.pi / 180.0;

/// 交通方式，由两个停留点之间的平均速度反推。
enum TravelMode { stay, walk, drive, fly }

/// 一个"停留点"= 行程里的一个节点。
class StayPoint {
  final int seq;
  final double lat;
  final double lon;
  final DateTime arrive;
  final DateTime leave;
  final List<String> photoIds;

  StayPoint({
    required this.seq,
    required this.lat,
    required this.lon,
    required this.arrive,
    required this.leave,
    required this.photoIds,
  });

  Duration get duration => leave.difference(arrive);
  int get photoCount => photoIds.length;

  /// 停留超过 5 小时且跨过凌晨，基本可判定是过夜点 —— 用来切分"天"。
  bool get isOvernight =>
      duration.inHours >= 5 && arrive.day != leave.day;

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'lat': lat,
        'lon': lon,
        'arrive': arrive.toIso8601String(),
        'leave': leave.toIso8601String(),
        'photo_ids': photoIds,
      };
}

/// 两个停留点之间的移动段。
class Leg {
  final StayPoint from;
  final StayPoint to;
  final double meters;
  final Duration duration;

  const Leg({
    required this.from,
    required this.to,
    required this.meters,
    required this.duration,
  });

  double get kmPerHour {
    final h = duration.inSeconds / 3600.0;
    return h <= 0 ? 0 : (meters / 1000.0) / h;
  }

  /// 速度反推交通方式。飞行段在地图上要画大圆弧虚线，不能画直线。
  TravelMode get mode {
    if (meters < 200) return TravelMode.stay;
    final v = kmPerHour;
    if (v > 300) return TravelMode.fly;
    if (v > 12) return TravelMode.drive;
    return TravelMode.walk;
  }
}

/// 一次行程还原出来的路线。
class TripRoute {
  final List<StayPoint> stays;
  final List<Leg> legs;

  const TripRoute(this.stays, this.legs);

  bool get isEmpty => stays.isEmpty;

  double get totalMeters =>
      legs.fold<double>(0, (a, l) => a + l.meters);

  double get totalKm => totalMeters / 1000.0;
  double get totalMiles => totalMeters / 1609.344;

  DateTime? get start => stays.isEmpty ? null : stays.first.arrive;
  DateTime? get end => stays.isEmpty ? null : stays.last.leave;

  /// 自然日天数（按本地时间，跨时区时以照片当地时间为准，这正是用户体验到的）
  int get dayCount {
    if (stays.isEmpty) return 0;
    final days = stays.map((s) => _dayKey(s.arrive)).toSet();
    return days.length;
  }

  /// 按自然日分组，用于"Day 1 / Day 2"的展示
  Map<String, List<StayPoint>> get byDay {
    final m = <String, List<StayPoint>>{};
    for (final s in stays) {
      m.putIfAbsent(_dayKey(s.arrive), () => []).add(s);
    }
    return m;
  }

  static String _dayKey(DateTime t) =>
      '${t.year}-${_p2(t.month)}-${_p2(t.day)}';
  static String _p2(int n) => n.toString().padLeft(2, '0');
}

/// 停留点聚类的参数。默认值针对**自驾长途 + 照片稀疏采样**调过。
///
/// 注意这不是 GPS 轨迹日志：照片是稀疏且不均匀的采样，
/// 所以用"离开半径或时间断裂就开新簇"的增量聚类，比经典的
/// 滑动窗口停留点检测更稳。
class ClusterOptions {
  /// 超出这个半径就认为离开了当前地点
  final double radiusMeters;

  /// 相邻两张照片间隔超过这么久，即使位置没变也切成两个节点
  /// （例如在同一个营地待了一夜，早晚应当算两次停留）
  final Duration maxGap;

  /// 少于这个张数的簇会被合并进相邻簇，避免路上随手拍产生大量碎片节点
  final int minPhotos;

  const ClusterOptions({
    this.radiusMeters = 800,
    this.maxGap = const Duration(minutes: 90),
    this.minPhotos = 1,
  });

  /// 城市内游玩：半径更小，节点更密
  static const city = ClusterOptions(
    radiusMeters: 300,
    maxGap: Duration(minutes: 45),
  );

  /// 长途自驾：半径更大，避免高速路上每个服务区都成一个节点
  static const roadTrip = ClusterOptions(
    radiusMeters: 1500,
    maxGap: Duration(minutes: 120),
    minPhotos: 2,
  );
}

/// 从带 GPS 的照片还原行程路线。
///
/// 这是整个产品的核心算法：把一堆散点变成"去过哪里、按什么顺序、怎么去的"。
TripRoute buildRoute(
  Iterable<PhotoRecord> photos, {
  ClusterOptions options = const ClusterOptions(),
}) {
  final pts = photos.where((p) => p.hasLocation).toList()
    ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  if (pts.isEmpty) return const TripRoute([], []);

  final clusters = <_Cluster>[];
  var current = _Cluster()..add(pts.first);

  for (var i = 1; i < pts.length; i++) {
    final p = pts[i];
    final gap = p.takenAt.difference(current.lastTime);
    final d = haversineMeters(current.lat, current.lon, p.lat!, p.lon!);

    if (d > options.radiusMeters || gap > options.maxGap) {
      clusters.add(current);
      current = _Cluster();
    }
    current.add(p);
  }
  clusters.add(current);

  // 合并太小的簇: 并进时间上更近的那个邻居，而不是粗暴丢弃
  if (options.minPhotos > 1) {
    _mergeSmall(clusters, options);
  }

  final stays = <StayPoint>[];
  for (var i = 0; i < clusters.length; i++) {
    final c = clusters[i];
    stays.add(StayPoint(
      seq: i,
      lat: c.lat,
      lon: c.lon,
      arrive: c.firstTime,
      leave: c.lastTime,
      photoIds: c.ids,
    ));
  }

  final legs = <Leg>[];
  for (var i = 0; i + 1 < stays.length; i++) {
    final a = stays[i], b = stays[i + 1];
    legs.add(Leg(
      from: a,
      to: b,
      meters: haversineMeters(a.lat, a.lon, b.lat, b.lon),
      duration: b.arrive.difference(a.leave),
    ));
  }

  return TripRoute(stays, legs);
}

void _mergeSmall(List<_Cluster> clusters, ClusterOptions options) {
  var i = 0;
  while (i < clusters.length && clusters.length > 1) {
    if (clusters[i].ids.length >= options.minPhotos) {
      i++;
      continue;
    }
    final prevGap = i > 0
        ? clusters[i].firstTime.difference(clusters[i - 1].lastTime)
        : const Duration(days: 3650);
    final nextGap = i + 1 < clusters.length
        ? clusters[i + 1].firstTime.difference(clusters[i].lastTime)
        : const Duration(days: 3650);
    final target = prevGap <= nextGap ? i - 1 : i + 1;
    if (target < 0 || target >= clusters.length) {
      i++;
      continue;
    }
    clusters[target].absorb(clusters[i]);
    clusters.removeAt(i);
    if (target < i) i = target + 1;
  }
}

class _Cluster {
  final List<String> ids = [];
  double _sumLat = 0, _sumLon = 0;
  late DateTime firstTime;
  late DateTime lastTime;

  double get lat => _sumLat / ids.length;
  double get lon => _sumLon / ids.length;

  void add(PhotoRecord p) {
    if (ids.isEmpty) {
      firstTime = p.takenAt;
      lastTime = p.takenAt;
    } else {
      if (p.takenAt.isBefore(firstTime)) firstTime = p.takenAt;
      if (p.takenAt.isAfter(lastTime)) lastTime = p.takenAt;
    }
    ids.add(p.id);
    _sumLat += p.lat!;
    _sumLon += p.lon!;
  }

  void absorb(_Cluster other) {
    ids.addAll(other.ids);
    _sumLat += other._sumLat;
    _sumLon += other._sumLon;
    if (other.firstTime.isBefore(firstTime)) firstTime = other.firstTime;
    if (other.lastTime.isAfter(lastTime)) lastTime = other.lastTime;
  }
}
