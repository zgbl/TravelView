import 'models.dart';
import 'polyline_codec.dart';
import 'route.dart';
import 'routing.dart';

/// Story —— **所有输出形态的唯一数据源**。
///
/// Web Story、视频、社交图包都从这一份数据渲染，不各写一套。
/// 它是一份纯 JSON manifest（几十 KB），加上一批派生图（每张 100-300KB）。
/// **原图永远不在里面，也永远不上传。**
///
/// 生成一次、永久有效: 网页打开时不调用任何外部 API，
/// 路线、坐标、文案全都已经在 manifest 里。
class Story {
  static const int formatVersion = 1;

  final String id;
  final String slug;
  final String title;
  final String? subtitle;
  final DateTime start;
  final DateTime end;
  final String? coverPhotoId;
  final String template;

  final List<StoryDay> days;
  final List<StoryStop> stops;
  final List<StoryPhoto> photos;
  final List<StoryRoute> routes;

  /// 地图上那条线要走的**全部**地理点，按时间顺序。
  ///
  /// **和 [stops] 是两件事，不要合并。** stops 是叙事单位（章），
  /// 一篇游记只该有十来个，否则没人写得完也没人读得完；
  /// path 是地理轨迹，自驾路上停车拍照一天二十次，
  /// 每一个点都得在线上，少一个路线的形状就不是他走过的那条路了。
  ///
  /// 有真实路网数据（[routes]）时以那个为准，path 是没有路网时的底。
  final List<LatLon> path;

  const Story({
    required this.id,
    required this.slug,
    required this.title,
    this.subtitle,
    required this.start,
    required this.end,
    this.coverPhotoId,
    this.template = 'classic',
    required this.days,
    required this.stops,
    required this.photos,
    required this.routes,
    this.path = const [],
  });

  int get dayCount => days.length;
  int get stopCount => stops.length;
  int get photoCount => photos.length;

  double get distanceMeters =>
      routes.fold<double>(0, (a, r) => a + r.distanceMeters);

  double get distanceMiles => distanceMeters / 1609.344;
  double get distanceKm => distanceMeters / 1000.0;

  /// 结束卡片上的数字。**这张卡是给人截图发出去的**，所以要好读。
  Map<String, String> get summary => {
        '天数': '$dayCount',
        '站点': '$stopCount',
        '里程': '${distanceMiles.round()} mi',
        '照片': '$photoCount',
      };

  Map<String, dynamic> toJson() => {
        'version': formatVersion,
        'id': id,
        'slug': slug,
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        if (coverPhotoId != null) 'cover': coverPhotoId,
        'template': template,
        'stats': {
          'days': dayCount,
          'stops': stopCount,
          'photos': photoCount,
          'distanceMeters': distanceMeters.round(),
        },
        'days': days.map((e) => e.toJson()).toList(),
        'stops': stops.map((e) => e.toJson()).toList(),
        'photos': photos.map((e) => e.toJson()).toList(),
        'routes': routes.map((e) => e.toJson()).toList(),
        // 扁平的 [lat, lon] 数对，前端直接喂给 Leaflet。
        // 几十个点几 KB，没必要为它上编码
        if (path.isNotEmpty)
          'path': [for (final p in path) [p.lat, p.lon]],
      };

  factory Story.fromJson(Map<String, dynamic> j) => Story(
        id: j['id'] as String,
        slug: j['slug'] as String,
        title: j['title'] as String,
        subtitle: j['subtitle'] as String?,
        start: DateTime.parse(j['start'] as String),
        end: DateTime.parse(j['end'] as String),
        coverPhotoId: j['cover'] as String?,
        template: j['template'] as String? ?? 'classic',
        days: (j['days'] as List)
            .map((e) => StoryDay.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        stops: (j['stops'] as List)
            .map((e) => StoryStop.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        photos: (j['photos'] as List)
            .map((e) => StoryPhoto.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        routes: (j['routes'] as List)
            .map((e) => StoryRoute.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        path: [
          for (final e in (j['path'] as List? ?? const []))
            LatLon((e as List)[0] as double, e[1] as double),
        ],
      );
}

class StoryDay {
  final String date; // 2025-09-04
  final String? label; // "Chicago" / "Chicago -> Evanston"
  final List<String> stopIds;

  const StoryDay({required this.date, this.label, required this.stopIds});

  Map<String, dynamic> toJson() => {
        'date': date,
        if (label != null) 'label': label,
        'stops': stopIds,
      };

  factory StoryDay.fromJson(Map<String, dynamic> j) => StoryDay(
        date: j['date'] as String,
        label: j['label'] as String?,
        stopIds: (j['stops'] as List).cast<String>(),
      );
}

class StoryStop {
  final String id;
  final int seq;
  final String? name; // 站点标题: 用户写的，或反查到的地名
  final String? note; // 这一站的说明文字
  /// 英文版。**网页是双语的**，英文读者看到的不该是中文正文。
  /// 没有译文时前端回落到 name/note。
  final String? nameEn;
  final String? noteEn;
  final double lat;
  final double lon;
  final DateTime arrive;
  final DateTime leave;
  final String? heroPhotoId;
  final List<String> photoIds;

  const StoryStop({
    required this.id,
    required this.seq,
    this.name,
    this.note,
    this.nameEn,
    this.noteEn,
    required this.lat,
    required this.lon,
    required this.arrive,
    required this.leave,
    this.heroPhotoId,
    required this.photoIds,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'seq': seq,
        if (name != null) 'name': name,
        if (note != null && note!.isNotEmpty) 'note': note,
        if (nameEn != null && nameEn!.isNotEmpty) 'nameEn': nameEn,
        if (noteEn != null && noteEn!.isNotEmpty) 'noteEn': noteEn,
        'lat': lat,
        'lon': lon,
        'arrive': arrive.toIso8601String(),
        'leave': leave.toIso8601String(),
        if (heroPhotoId != null) 'hero': heroPhotoId,
        'photos': photoIds,
      };

  factory StoryStop.fromJson(Map<String, dynamic> j) => StoryStop(
        id: j['id'] as String,
        seq: (j['seq'] as num).toInt(),
        name: j['name'] as String?,
        note: j['note'] as String?,
        nameEn: j['nameEn'] as String?,
        noteEn: j['noteEn'] as String?,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        arrive: DateTime.parse(j['arrive'] as String),
        leave: DateTime.parse(j['leave'] as String),
        heroPhotoId: j['hero'] as String?,
        photoIds: (j['photos'] as List).cast<String>(),
      );
}

/// 发布出去的照片。**只有派生版本，没有原图。**
class StoryPhoto {
  final String id;
  final DateTime takenAt;
  final double? lat;
  final double? lon;

  /// 网页用的主图，长边约 1200-1600
  final String webPath;
  final int webWidth;
  final int webHeight;

  /// 列表和占位用的小图
  final String? thumbPath;

  final String? caption;

  const StoryPhoto({
    required this.id,
    required this.takenAt,
    this.lat,
    this.lon,
    required this.webPath,
    required this.webWidth,
    required this.webHeight,
    this.thumbPath,
    this.caption,
  });

  bool get isPortrait => webHeight > webWidth;
  double get aspect => webWidth / webHeight;

  Map<String, dynamic> toJson() => {
        'id': id,
        'takenAt': takenAt.toIso8601String(),
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        'web': {'path': webPath, 'w': webWidth, 'h': webHeight},
        if (thumbPath != null) 'thumb': thumbPath,
        if (caption != null) 'caption': caption,
      };

  factory StoryPhoto.fromJson(Map<String, dynamic> j) {
    final web = Map<String, dynamic>.from(j['web'] as Map);
    return StoryPhoto(
      id: j['id'] as String,
      takenAt: DateTime.parse(j['takenAt'] as String),
      lat: (j['lat'] as num?)?.toDouble(),
      lon: (j['lon'] as num?)?.toDouble(),
      webPath: web['path'] as String,
      webWidth: (web['w'] as num).toInt(),
      webHeight: (web['h'] as num).toInt(),
      thumbPath: j['thumb'] as String?,
      caption: j['caption'] as String?,
    );
  }
}

/// manifest 里的路线。**geometry 存编码后的 polyline6，不是坐标数组** ——
/// 体积小四五倍，渲染时解回来即可。
class StoryRoute {
  final String fromStopId;
  final String toStopId;
  final String mode;
  final String source;
  final String provider;
  final double distanceMeters;
  final int? durationSeconds;
  final String encodedGeometry;
  final int precision;

  const StoryRoute({
    required this.fromStopId,
    required this.toStopId,
    required this.mode,
    required this.source,
    required this.provider,
    required this.distanceMeters,
    this.durationSeconds,
    required this.encodedGeometry,
    this.precision = 6,
  });

  factory StoryRoute.fromLeg(RouteLeg leg) => StoryRoute(
        fromStopId: leg.fromStopId,
        toStopId: leg.toStopId,
        mode: leg.mode.name,
        source: leg.source.name,
        provider: leg.provider,
        distanceMeters: leg.distanceMeters,
        durationSeconds: leg.duration?.inSeconds,
        encodedGeometry: PolylineCodec.encode(leg.geometry),
      );

  List<LatLon> decodeGeometry() =>
      PolylineCodec.decode(encodedGeometry, precision: precision);

  Map<String, dynamic> toJson() => {
        'from': fromStopId,
        'to': toStopId,
        'mode': mode,
        'source': source,
        'provider': provider,
        'distanceMeters': distanceMeters.round(),
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
        'geometry': encodedGeometry,
        'precision': precision,
      };

  factory StoryRoute.fromJson(Map<String, dynamic> j) => StoryRoute(
        fromStopId: j['from'] as String,
        toStopId: j['to'] as String,
        mode: j['mode'] as String,
        source: j['source'] as String,
        provider: j['provider'] as String,
        distanceMeters: (j['distanceMeters'] as num).toDouble(),
        durationSeconds: (j['durationSeconds'] as num?)?.toInt(),
        encodedGeometry: j['geometry'] as String,
        precision: (j['precision'] as num?)?.toInt() ?? 6,
      );
}

/// 从已有的行程数据装配出 Story。
///
/// 纯函数、不碰磁盘、不联网 —— 所以可以完整测试。
/// 真正的图片转码和上传由调用方负责，这里只负责结构。
class StoryBuilder {
  /// [webPathOf] 给出每张照片在发布包里的相对路径，例如 photos/p1.webp
  static Story build({
    required String id,
    required String slug,
    required String title,
    String? subtitle,
    String template = 'classic',
    required TripRoute trip,
    required Map<String, PhotoRecord> recordsById,
    required Set<String> selectedIds,
    required Map<int, String?> heroByStopSeq,
    /// 用户指定的片头封面。**这是整篇 Story 第一眼看到的那张**，
    /// 也是分享到社交平台时的缩略图，不该由"第一站的第一张"决定。
    /// 传空或者这张没被选进 Story 时，回落到第一站的首图。
    String? coverPhotoId,
    required List<RouteLeg> legs,
    /// 地图轨迹的全部地理点（合并章之前的那份）。见 [Story.path]。
    List<LatLon> pathPoints = const [],
    required String Function(PhotoRecord) webPathOf,
    String Function(PhotoRecord)? thumbPathOf,
    Map<int, String>? stopNames,
    Map<int, String>? stopNotes,
    Map<int, String>? stopNamesEn,
    Map<int, String>? stopNotesEn,
  }) {
    String stopId(int seq) => 'stop-$seq';

    final photos = <StoryPhoto>[];
    final stops = <StoryStop>[];

    for (final stop in trip.stays) {
      final picked = stop.photoIds
          .where(selectedIds.contains)
          .map((pid) => recordsById[pid])
          .whereType<PhotoRecord>()
          .toList()
        ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
      if (picked.isEmpty) continue; // 没选照片的站不进 Story

      for (final r in picked) {
        photos.add(StoryPhoto(
          id: r.id,
          takenAt: r.takenAt,
          lat: r.lat,
          lon: r.lon,
          webPath: webPathOf(r),
          webWidth: r.width ?? 1600,
          webHeight: r.height ?? 1200,
          thumbPath: thumbPathOf?.call(r),
        ));
      }

      final hero = heroByStopSeq[stop.seq];
      stops.add(StoryStop(
        id: stopId(stop.seq),
        seq: stop.seq,
        name: stopNames?[stop.seq],
        note: stopNotes?[stop.seq],
        nameEn: stopNamesEn?[stop.seq],
        noteEn: stopNotesEn?[stop.seq],
        lat: stop.lat,
        lon: stop.lon,
        arrive: stop.arrive,
        leave: stop.leave,
        heroPhotoId:
            picked.any((e) => e.id == hero) ? hero : picked.first.id,
        photoIds: picked.map((e) => e.id).toList(),
      ));
    }

    // 按自然日分组
    final dayMap = <String, List<String>>{};
    for (final s in stops) {
      final key = _dayKey(s.arrive);
      dayMap.putIfAbsent(key, () => []).add(s.id);
    }
    final days = (dayMap.keys.toList()..sort())
        .map((d) => StoryDay(date: d, stopIds: dayMap[d]!))
        .toList();

    // 路线要**接起来**，不能只挑两端都在 Story 里的那几段。
    //
    // 中间的站常常一张照片都没选（路上随手拍的），如果直接丢掉跨越它的
    // 路段，Story 里就会既没有那截路，总里程也变成 0 ——
    // 而人是真的开过去了。所以把被跳过的站之间的路段**首尾拼成一段**。
    final routes = _stitchRoutes(trip, stops, legs);

    final picked = photos.any((p) => p.id == coverPhotoId);
    final cover = picked
        ? coverPhotoId
        : (stops.isEmpty ? null : stops.first.heroPhotoId);

    return Story(
      id: id,
      slug: slug,
      title: title,
      subtitle: subtitle,
      start: stops.isEmpty ? DateTime.now() : stops.first.arrive,
      end: stops.isEmpty ? DateTime.now() : stops.last.leave,
      coverPhotoId: cover,
      template: template,
      days: days,
      stops: stops,
      photos: photos,
      routes: routes,
      path: pathPoints,
    );
  }

  /// 把跨越"没选照片的站"的若干路段合并成一段。
  /// 缺任何一截就整段放弃 —— 宁可没有，也不要画一条假的路。
  static List<StoryRoute> _stitchRoutes(
      TripRoute trip, List<StoryStop> stops, List<RouteLeg> legs) {
    if (stops.length < 2) return const [];
    final byPair = <String, RouteLeg>{
      for (final l in legs) '${l.fromStopId}>${l.toStopId}': l,
    };
    final order = trip.stays.map((e) => 'stop-${e.seq}').toList();
    final indexOf = {for (var i = 0; i < order.length; i++) order[i]: i};

    final out = <StoryRoute>[];
    for (var i = 0; i + 1 < stops.length; i++) {
      final a = indexOf[stops[i].id];
      final b = indexOf[stops[i + 1].id];
      if (a == null || b == null || b <= a) continue;

      final chain = <RouteLeg>[];
      for (var k = a; k < b; k++) {
        final leg = byPair['${order[k]}>${order[k + 1]}'];
        if (leg == null) {
          chain.clear();
          break;
        }
        chain.add(leg);
      }
      if (chain.isEmpty) continue;
      if (chain.length == 1) {
        out.add(StoryRoute.fromLeg(chain.first));
        continue;
      }

      final geometry = <LatLon>[];
      var meters = 0.0;
      var seconds = 0;
      var hasDuration = false;
      for (final l in chain) {
        meters += l.distanceMeters;
        if (l.duration != null) {
          seconds += l.duration!.inSeconds;
          hasDuration = true;
        }
        for (final pt in l.geometry) {
          // 接缝处上一段的终点和下一段的起点是同一个点，去掉一个
          if (geometry.isNotEmpty &&
              geometry.last.lat == pt.lat &&
              geometry.last.lon == pt.lon) {
            continue;
          }
          geometry.add(pt);
        }
      }
      // 只要有一截是直线猜的，整段就不能声称是实际道路
      final source = chain.every((l) => l.source == RouteSource.actual)
          ? RouteSource.actual
          : chain.any((l) => l.source == RouteSource.inferred)
              ? RouteSource.inferred
              : RouteSource.reconstructed;

      out.add(StoryRoute(
        fromStopId: stops[i].id,
        toStopId: stops[i + 1].id,
        mode: chain.first.mode.name,
        source: source.name,
        provider: chain.first.provider,
        distanceMeters: meters,
        durationSeconds: hasDuration ? seconds : null,
        encodedGeometry: PolylineCodec.encode(geometry),
      ));
    }
    return out;
  }

  static String _dayKey(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }
}
