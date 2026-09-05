import 'dart:convert';

import 'package:test/test.dart';
import 'package:tv_core/tv_core.dart';

PhotoRecord ph(String id, DateTime t, double lat, double lon,
        {int w = 4032, int h = 3024}) =>
    PhotoRecord(
      id: id,
      takenAt: t,
      bytes: 3000000,
      origFilename: '$id.HEIC',
      lat: lat,
      lon: lon,
      width: w,
      height: h,
    );

void main() {
  final base = DateTime(2025, 9, 4, 9);

  // 两站: 芝加哥 -> 克利夫兰
  final records = <PhotoRecord>[
    ph('c1', base, 41.882, -87.635),
    ph('c2', base.add(const Duration(minutes: 10)), 41.883, -87.636),
    ph('c3', base.add(const Duration(minutes: 20)), 41.884, -87.637),
    ph('e1', base.add(const Duration(hours: 6)), 41.499, -81.694),
    ph('e2', base.add(const Duration(hours: 6, minutes: 10)), 41.500, -81.695,
        w: 3024, h: 4032),
  ];
  final byId = {for (final r in records) r.id: r};

  Story buildStory({Set<String>? selected}) {
    final trip = buildRoute(records, options: ClusterOptions.roadTrip);
    final legs = [
      RouteLeg(
        fromStopId: 'stop-0',
        toStopId: 'stop-1',
        mode: TravelMode2.driving,
        source: RouteSource.inferred,
        provider: 'osrm',
        distanceMeters: 555000,
        duration: const Duration(hours: 5, minutes: 30),
        geometry: const [
          LatLon(41.882, -87.635),
          LatLon(41.7, -85.0),
          LatLon(41.499, -81.694),
        ],
      ),
    ];
    return StoryBuilder.build(
      id: 'story-1',
      slug: '9f3a2b',
      title: '横穿美国 2025',
      subtitle: '9 月 4 日 - 9 月 5 日',
      trip: trip,
      recordsById: byId,
      selectedIds: selected ?? {'c1', 'c3', 'e1'},
      heroByStopSeq: {0: 'c3', 1: 'e1'},
      legs: legs,
      webPathOf: (r) => 'photos/${r.id}.webp',
      thumbPathOf: (r) => 'thumbs/${r.id}.webp',
    );
  }

  group('装配 Story', () {
    test('只收进被选中的照片', () {
      final s = buildStory();
      expect(s.photoCount, 3);
      expect(s.photos.map((e) => e.id), containsAll(['c1', 'c3', 'e1']));
      expect(s.photos.map((e) => e.id), isNot(contains('c2')));
    });

    test('没选照片的站不进 Story', () {
      final s = buildStory(selected: {'c1'});
      expect(s.stopCount, 1);
      expect(s.stops.single.id, 'stop-0');
    });

    test('两端都在才保留路线段', () {
      final s = buildStory(selected: {'c1'});
      expect(s.routes, isEmpty, reason: '终点站被剔掉了，这段路线不该留着');
    });

    test('封面取第一站的 hero', () {
      final s = buildStory();
      expect(s.stops.first.heroPhotoId, 'c3');
      expect(s.coverPhotoId, 'c3');
    });

    test('hero 没被选中时退回该站第一张', () {
      final s = buildStory(selected: {'c1', 'e1'});
      expect(s.stops.first.heroPhotoId, 'c1');
    });

    test('按自然日分组', () {
      final s = buildStory();
      expect(s.days.length, 1);
      expect(s.days.single.date, '2025-09-04');
      expect(s.days.single.stopIds.length, 2);
    });

    test('统计数字可直接上结束卡片', () {
      final s = buildStory();
      expect(s.summary['站点'], '2');
      expect(s.summary['照片'], '3');
      expect(s.distanceMiles, closeTo(345, 10));
    });

    test('照片只有派生版本，不含原图路径', () {
      final s = buildStory();
      final j = jsonEncode(s.toJson());
      expect(j, contains('photos/c1.webp'));
      expect(j, isNot(contains('.HEIC')),
          reason: 'manifest 里绝不能出现原图');
    });

    test('竖图能被识别，渲染时要用不同的版式', () {
      final s = buildStory(selected: {'c1', 'e2'});
      final portrait = s.photos.firstWhere((e) => e.id == 'e2');
      expect(portrait.isPortrait, isTrue);
    });
  });

  group('manifest 序列化', () {
    test('存下来再读回来完全一致', () {
      final s = buildStory();
      final back = Story.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.title, s.title);
      expect(back.slug, s.slug);
      expect(back.photoCount, s.photoCount);
      expect(back.stopCount, s.stopCount);
      expect(back.days.length, s.days.length);
      expect(back.routes.length, s.routes.length);
      expect(back.distanceMeters, closeTo(s.distanceMeters, 1));
    });

    test('路线存的是编码串，不是坐标数组', () {
      final s = buildStory();
      final j = s.toJson();
      final route = (j['routes'] as List).first as Map<String, dynamic>;
      expect(route['geometry'], isA<String>());
      expect(route['precision'], 6);
      expect(route['source'], 'inferred');
      expect(route['provider'], 'osrm');
    });

    test('编码的路线能解回原坐标', () {
      final s = buildStory();
      final pts = s.routes.first.decodeGeometry();
      expect(pts.length, 3);
      expect(pts.first.lat, closeTo(41.882, 1e-6));
      expect(pts.last.lon, closeTo(-81.694, 1e-6));
    });

    test('manifest 体积够小，适合手机秒开', () {
      final s = buildStory();
      final bytes = utf8.encode(jsonEncode(s.toJson())).length;
      expect(bytes, lessThan(4096));
    });
  });

  group('路线拼接', () {
    // 三站，中间那站一张照片都没选 —— 真实情况里这非常常见
    final rec = <PhotoRecord>[
      ph('a1', base, 41.882, -87.635),
      ph('b1', base.add(const Duration(hours: 3)), 41.65, -83.53),
      ph('c1', base.add(const Duration(hours: 6)), 41.499, -81.694),
    ];
    final trip = buildRoute(rec, options: ClusterOptions.roadTrip);

    List<RouteLeg> legsOf() => [
          RouteLeg(
            fromStopId: 'stop-0',
            toStopId: 'stop-1',
            mode: TravelMode2.driving,
            source: RouteSource.actual,
            provider: 'ors',
            distanceMeters: 380000,
            duration: const Duration(hours: 3),
            geometry: const [
              LatLon(41.882, -87.635),
              LatLon(41.75, -85.0),
              LatLon(41.65, -83.53),
            ],
          ),
          RouteLeg(
            fromStopId: 'stop-1',
            toStopId: 'stop-2',
            mode: TravelMode2.driving,
            source: RouteSource.actual,
            provider: 'ors',
            distanceMeters: 180000,
            duration: const Duration(hours: 2),
            geometry: const [
              LatLon(41.65, -83.53),
              LatLon(41.55, -82.5),
              LatLon(41.499, -81.694),
            ],
          ),
        ];

    Story storyWith(Set<String> selected) => StoryBuilder.build(
          id: 's',
          slug: 'x',
          title: 't',
          trip: trip,
          recordsById: {for (final r in rec) r.id: r},
          selectedIds: selected,
          heroByStopSeq: const {},
          legs: legsOf(),
          webPathOf: (r) => 'photos/${r.id}.webp',
        );

    test('中间的站没选照片时，路线接起来而不是消失', () {
      final s = storyWith({'a1', 'c1'});
      expect(s.stops.length, 2);
      expect(s.routes.length, 1, reason: '两段应该拼成一段');
      expect(s.routes.first.fromStopId, s.stops.first.id);
      expect(s.routes.first.toStopId, s.stops.last.id);
    });

    test('总里程不能变成 0 —— 人是真的开过去了', () {
      final s = storyWith({'a1', 'c1'});
      expect(s.distanceMeters, 560000);
      expect(s.distanceMiles, greaterThan(300));
    });

    test('接缝处不留重复点', () {
      final pts = storyWith({'a1', 'c1'}).routes.first.decodeGeometry();
      expect(pts.length, 5);
    });

    test('每站都有照片时不做拼接', () {
      final s = storyWith({'a1', 'b1', 'c1'});
      expect(s.routes.length, 2);
      expect(s.distanceMeters, 560000);
    });
  });

  test('没有任何路线时，Story 里也不该假装有', () {
    // 兜底逻辑在 App 那一层（legsForStory），这里守住 Story 本身的诚实:
    // 没给 legs 就没有 routes，绝不凭空连线
    final s = StoryBuilder.build(
      id: 's', slug: 'x', title: 't',
      trip: buildRoute(records, options: ClusterOptions.roadTrip),
      recordsById: byId,
      selectedIds: {'c1', 'e1'},
      heroByStopSeq: const {},
      legs: const [],
      webPathOf: (r) => 'photos/${r.id}.webp',
    );
    expect(s.routes, isEmpty);
    expect(s.distanceMeters, 0);
  });
}

