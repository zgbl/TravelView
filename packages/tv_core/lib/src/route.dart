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

/// 一「站」= 行程里的一个停留点。UI 上称作"站"（第 3 站），
/// 因为它天然带路线感，和 TOKYO - HAKONE - KYOTO 是同一个心智模型。
class Stop {
  final int seq;
  final double lat;
  final double lon;
  final DateTime arrive;
  final DateTime leave;
  final List<String> photoIds;

  /// 进出这一站的实际位置。
  ///
  /// 路线规划**不能用簇中心**: 在一个城市里拍了 80 张照片，中心点可能落在
  /// 谁都没去过的地方，两站之间连出来的路会绕得莫名其妙。
  /// 用"最早那张照片的位置"作为入口、"最晚那张"作为出口，贴近真实动线。
  final double? entryLat;
  final double? entryLon;
  final double? exitLat;
  final double? exitLon;

  Stop({
    required this.seq,
    required this.lat,
    required this.lon,
    required this.arrive,
    required this.leave,
    required this.photoIds,
    this.entryLat,
    this.entryLon,
    this.exitLat,
    this.exitLon,
  });

  double get routeEntryLat => entryLat ?? lat;
  double get routeEntryLon => entryLon ?? lon;
  double get routeExitLat => exitLat ?? lat;
  double get routeExitLon => exitLon ?? lon;

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
  final Stop from;
  final Stop to;
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
  final List<Stop> stays;
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
  Map<String, List<Stop>> get byDay {
    final m = <String, List<Stop>>{};
    for (final s in stays) {
      m.putIfAbsent(_dayKey(s.arrive), () => []).add(s);
    }
    return m;
  }

  static String _dayKey(DateTime t) =>
      '${t.year}-${_p2(t.month)}-${_p2(t.day)}';
  static String _p2(int n) => n.toString().padLeft(2, '0');
}

/// 站点聚类的参数。默认值针对**自驾长途 + 照片稀疏采样**调过。
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

  final stays = <Stop>[];
  for (var i = 0; i < clusters.length; i++) {
    final c = clusters[i];
    stays.add(Stop(
      seq: i,
      lat: c.lat,
      lon: c.lon,
      arrive: c.firstTime,
      leave: c.lastTime,
      photoIds: c.ids,
      entryLat: c.firstLat,
      entryLon: c.firstLon,
      exitLat: c.lastLat,
      exitLon: c.lastLon,
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
  // 最早/最晚那张照片的位置 —— 用作这一站的进出口
  double? firstLat, firstLon, lastLat, lastLon;

  double get lat => _sumLat / ids.length;
  double get lon => _sumLon / ids.length;

  void add(PhotoRecord p) {
    if (ids.isEmpty) {
      firstTime = p.takenAt;
      lastTime = p.takenAt;
      firstLat = p.lat;
      firstLon = p.lon;
      lastLat = p.lat;
      lastLon = p.lon;
    } else {
      if (p.takenAt.isBefore(firstTime)) {
        firstTime = p.takenAt;
        firstLat = p.lat;
        firstLon = p.lon;
      }
      if (p.takenAt.isAfter(lastTime)) {
        lastTime = p.takenAt;
        lastLat = p.lat;
        lastLon = p.lon;
      }
    }
    ids.add(p.id);
    _sumLat += p.lat!;
    _sumLon += p.lon!;
  }

  void absorb(_Cluster other) {
    ids.addAll(other.ids);
    _sumLat += other._sumLat;
    _sumLon += other._sumLon;
    if (other.firstTime.isBefore(firstTime)) {
      firstTime = other.firstTime;
      firstLat = other.firstLat;
      firstLon = other.firstLon;
    }
    if (other.lastTime.isAfter(lastTime)) {
      lastTime = other.lastTime;
      lastLat = other.lastLat;
      lastLon = other.lastLon;
    }
  }
}

/// 把细碎的站合并成**章**，同时**一个地理点都不丢**。
///
/// 这是两件被混为一谈的事，分开之后两边都对：
///
/// - **轨迹**是地理的。自驾路上停下来拍照，一天十几二十次很正常，
///   点和点之间隔着几十英里 —— 地图上那辆小车必须把每一个点都走一遍，
///   少一个，路线的形状就不是他走过的那条路了。轨迹用 [routePath]，
///   它取的是**合并前**的全部站点。
///
/// - **章**是叙事的。没有人会给 53 个站分别写一段话 ——
///   五十三个空输入框摆在面前，正常人的反应是一个都不填。
///   一篇游记该有几章，由**读和写的承受力**决定，不由 GPS 的碎片程度决定。
///
/// 所以：合并只改"要写几段字"，不改"车怎么走"。
///
/// **在哪儿断章**：按相邻两站之间的时间间隔排序，在最大的那几个空档上切。
/// 这不是随便选的指标 —— 一趟行程里时间空档最大的地方，恰好就是过夜、
/// 长途转移、吃一顿正餐这些人天然会当成"下一段"的位置。
/// 用距离或照片数来切都试得通，但都不如"隔了多久"贴近人的记忆方式。
///
/// [target] 想要几章。默认按天数估：一天大约 5 段，夹在 6 和 16 之间 ——
/// 少于 6 段，一趟旅行会被压成流水账；多于 16 段，没人写得完。
TripRoute mergeIntoChapters(TripRoute fine, {int? target}) {
  final stays = fine.stays;
  if (stays.length <= 1) return fine;

  final want = (target ?? (fine.dayCount * 5).clamp(6, 16))
      .clamp(1, stays.length);
  if (stays.length <= want) return fine;

  // 每个相邻缝隙的"空档有多大"。索引 i 表示 stays[i] 和 stays[i+1] 之间。
  final gaps = <({int at, Duration gap})>[
    for (var i = 0; i + 1 < stays.length; i++)
      (at: i, gap: stays[i + 1].arrive.difference(stays[i].leave)),
  ]..sort((a, b) => b.gap.compareTo(a.gap));

  // 取空档最大的 want-1 条缝作为章的边界
  final cuts = {for (final g in gaps.take(want - 1)) g.at};

  // 切成若干段，记下每段在 stays 里的下标范围 ——
  // 后面算距离要沿着**原始站点**走一遍，光有合并后的首尾点不够
  var ranges = <({int from, int to})>[];
  var from = 0;
  for (var i = 0; i < stays.length; i++) {
    if (cuts.contains(i) || i == stays.length - 1) {
      ranges.add((from: from, to: i));
      from = i + 1;
    }
  }

  // **自动分段时再扫一遍，把太薄的段并掉。**
  //
  // 光按时间空档切，会切出"一个站、一张照片"的段 —— 那是路边停两分钟
  // 拍的一张，前后正好各隔着一段长途。它在时间轴上确实是孤立的，
  // 但**不值得一个单独的标题和一段话**：用户看到那个空输入框只会觉得
  // 这个 app 在为难他。
  //
  // 用户自己定了段数就不做这一步 —— **他说几段就是几段。**
  // 自动的时候聪明一点，手动的时候老实一点。
  if (target == null) ranges = _dropThin(stays, ranges);

  final merged = [
    for (var c = 0; c < ranges.length; c++)
      _fuse(c, stays.sublist(ranges[c].from, ranges[c].to + 1)),
  ];

  // legs 按合并后的章重算，但**距离仍然沿原始站点累加** ——
  // 1177 公里是他真的开了 1177 公里，合并了章不等于路变短了。
  // 直接量两章锚点之间的直线距离会凭空少掉几百公里。
  final legs = <Leg>[];
  for (var c = 0; c + 1 < merged.length; c++) {
    var m = 0.0;
    for (var i = ranges[c].to; i < ranges[c + 1].to; i++) {
      m += haversineMeters(stays[i].routeExitLat, stays[i].routeExitLon,
          stays[i + 1].routeEntryLat, stays[i + 1].routeEntryLon);
    }
    legs.add(Leg(
      from: merged[c],
      to: merged[c + 1],
      meters: m,
      duration: merged[c + 1].arrive.difference(merged[c].leave),
    ));
  }

  return TripRoute(merged, legs);
}

/// 把照片太少的段并进邻居 —— 并进**空档更小**的那一边，
/// 因为空档小意味着这两段本来就挨得近，合起来读着不突兀。
List<({int from, int to})> _dropThin(
    List<Stop> stays, List<({int from, int to})> ranges,
    {int minPhotos = 3}) {
  int photos(({int from, int to}) r) {
    var n = 0;
    for (var i = r.from; i <= r.to; i++) {
      n += stays[i].photoCount;
    }
    return n;
  }

  final out = [...ranges];
  // 每轮只并一个，并完重新判断 —— 并过之后这一段可能就够厚了
  while (out.length > 3) {
    final k = out.indexWhere((r) => photos(r) < minPhotos);
    if (k < 0) break;

    int target;
    if (k == 0) {
      target = 1;
    } else if (k == out.length - 1) {
      target = k - 1;
    } else {
      final prevGap =
          stays[out[k].from].arrive.difference(stays[out[k - 1].to].leave);
      final nextGap =
          stays[out[k + 1].from].arrive.difference(stays[out[k].to].leave);
      target = prevGap <= nextGap ? k - 1 : k + 1;
    }
    final lo = k < target ? k : target;
    final hi = k < target ? target : k;
    out[lo] = (from: out[lo].from, to: out[hi].to);
    out.removeAt(hi);
  }
  return out;
}

/// 把连着的几个站揉成一章。
///
/// **锚点取照片最多的那个站，不取几何中心。** 一章里有一个待了两小时的
/// 景点和四个路边随手拍，中心点会落在高速公路中间某个谁都没停过的地方 ——
/// 地图上那个圆点应该落在他真的待过的地方。
Stop _fuse(int seq, List<Stop> group) {
  var anchor = group.first;
  for (final s in group) {
    if (s.photoCount > anchor.photoCount) anchor = s;
  }
  return Stop(
    seq: seq,
    lat: anchor.lat,
    lon: anchor.lon,
    arrive: group.first.arrive,
    leave: group.last.leave,
    photoIds: [for (final s in group) ...s.photoIds],
    // 进出点取这一章真正的首尾 —— 路线规划要贴真实动线
    entryLat: group.first.routeEntryLat,
    entryLon: group.first.routeEntryLon,
    exitLat: group.last.routeExitLat,
    exitLon: group.last.routeExitLon,
  );
}

/// 地图上那条线要画的**全部**点，按时间顺序。
///
/// 用的是**合并前**的站，所以合并章一个点都不会少 ——
/// 小车照样在每一个地理位置之间走一遍。
List<({double lat, double lon})> routePath(TripRoute fine) => [
      for (final s in fine.stays) (lat: s.lat, lon: s.lon),
    ];
