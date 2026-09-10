import 'package:tv_core/tv_core.dart';

/// 一段被自动认出来的行程。
class Trip {
  final List<PhotoRecord> photos;
  Trip(this.photos);

  DateTime get start => photos.first.takenAt;
  DateTime get end => photos.last.takenAt;
  /// 跨了几个**自然日**。
  ///
  /// 不能用 `end.difference(start).inDays + 1`：12月27日傍晚出发、
  /// 28日上午回来，间隔不到 24 小时，那个算法给出 1 天，
  /// 而界面上明明列着"第 1 天"和"第 2 天"两组照片，自相矛盾。
  int get days =>
      DateTime(end.year, end.month, end.day)
          .difference(DateTime(start.year, start.month, start.day))
          .inDays +
      1;

  Iterable<PhotoRecord> get located => photos.where((p) => p.hasLocation);

  /// 离家多远（这趟里两点之间的最大直线距离）。
  double get spanMeters {
    final ps = located.toList();
    if (ps.length < 2) return 0;
    var lo = 90.0, hi = -90.0, lo2 = 180.0, hi2 = -180.0;
    for (final p in ps) {
      lo = lo < p.lat! ? lo : p.lat!;
      hi = hi > p.lat! ? hi : p.lat!;
      lo2 = lo2 < p.lon! ? lo2 : p.lon!;
      hi2 = hi2 > p.lon! ? hi2 : p.lon!;
    }
    return haversineMeters(lo, lo2, hi, hi2);
  }

  PhotoRecord? get cover {
    for (final p in photos) {
      if (p.hasLocation && !p.isScreenshot) return p;
    }
    return photos.isEmpty ? null : photos.first;
  }
}

/// 把整个相册切成一段一段的行程。
///
/// **这是手机端唯一一处"猜用户意图"的地方，所以规则要能讲得清楚：**
/// 连续两张照片之间隔了超过 [gapHours] 小时，就当作两趟；
/// 切完之后只留下"看起来真的是出门了"的段落 —— 够多张、够多天、
/// 或者跑得够远。三个条件满足一个就行，因为一日游、一周宅家拍娃、
/// 和一次跨国飞行是三种完全不同的形状。
///
/// 猜错了不要紧：界面上永远有"自己选时间范围"这条路。**自动只是省事，
/// 不是唯一入口** —— 把自动当成唯一入口，用户第一次被切错就再也不信它了。
List<Trip> detectTrips(
  List<PhotoRecord> all, {
  double gapHours = 20,
  int minPhotos = 8,
  double minSpanKm = 25,
}) {
  final ps = all.where((p) => !p.isScreenshot).toList()
    ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  if (ps.isEmpty) return const [];

  final segments = <List<PhotoRecord>>[[ps.first]];
  for (var i = 1; i < ps.length; i++) {
    final gap = ps[i].takenAt.difference(ps[i - 1].takenAt).inMinutes / 60.0;
    if (gap > gapHours) {
      segments.add(<PhotoRecord>[]);
    }
    segments.last.add(ps[i]);
  }

  final trips = segments.map(Trip.new).where((t) {
    if (t.photos.length < minPhotos) return false;
    return t.days >= 2 || t.spanMeters >= minSpanKm * 1000;
  }).toList();

  // 新的排在前面 —— 刚回来的那趟才是用户想发的
  trips.sort((a, b) => b.start.compareTo(a.start));
  return trips;
}
