import 'package:flutter_test/flutter_test.dart';
import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

/// 造一条 n 站的行程。相邻两站之间自动生成一段 Leg。
///
/// 站点坐标刻意拉开（每站差 0.5 度，约 60 公里），免得落进
/// "两点太近" 的分支，测不到真正的规划路径。
TripRoute makeTrip(
  int stopCount, {
  Duration perLeg = const Duration(hours: 1),
  double metersPerLeg = 60000,
}) {
  final stays = <Stop>[
    for (var i = 0; i < stopCount; i++)
      Stop(
        seq: i,
        lat: 37.0 + i * 0.5,
        lon: -122.0 - i * 0.5,
        arrive: DateTime(2026, 3, 1 + i, 9),
        leave: DateTime(2026, 3, 1 + i, 17),
        photoIds: ['p$i'],
      ),
  ];
  final legs = <Leg>[
    for (var i = 0; i + 1 < stays.length; i++)
      Leg(
        from: stays[i],
        to: stays[i + 1],
        meters: metersPerLeg,
        duration: perLeg,
      ),
  ];
  return TripRoute(stays, legs);
}

void main() {
  group('routeProviderFrom', () {
    test('按设置挑服务，和桌面端同一套解读', () {
      expect(routeProviderFrom(AppSettings(routeProvider: 'direct')).name,
          'direct');
      expect(routeProviderFrom(AppSettings(routeProvider: 'osrm')).name, 'osrm');
      expect(routeProviderFrom(AppSettings(routeProvider: 'ors')).name,
          'openrouteservice');
      // 认不出的值走默认分支，不能抛
      expect(routeProviderFrom(AppSettings(routeProvider: '??')).name,
          'openrouteservice');
    });
  });

  group('planStoryLegs', () {
    // 这一条就是手机端那个 bug 的护栏:
    // 原来 publish_page 传的是 `legs: const []`，地图上只剩下几个孤零零的点。
    test('每一段都有几何 —— Story 里绝不能没有线', () async {
      final trip = makeTrip(5);
      final legs = await planStoryLegs(trip, AppSettings());

      expect(legs.length, trip.legs.length,
          reason: '段数必须和行程一致，否则地图上会凭空断一截');
      for (final l in legs) {
        expect(l.geometry.length, greaterThanOrEqualTo(2),
            reason: '${l.fromStopId}->${l.toStopId} 这段没有几何，'
                '故事页和分享预览图上都会缺一条线');
      }
    });

    test('没配 key 时退成直线，而不是抛异常或返回空', () async {
      // 手机端就是这个状态: 默认 ors，但没有填 key 的界面
      final legs = await planStoryLegs(
          makeTrip(4), AppSettings(routeProvider: 'ors', orsApiKey: ''));

      expect(legs, hasLength(3));
      expect(legs.every((l) => l.provider == 'direct'), isTrue,
          reason: '拿不到道路数据就该老实用直线，并且如实标成 direct');
      expect(legs.every((l) => l.geometry.length >= 2), isTrue);
    });

    test('direct 模式产出两点直线，距离用大圆距离', () async {
      final legs = await planStoryLegs(
          makeTrip(3), AppSettings(routeProvider: 'direct'));

      expect(legs, hasLength(2));
      for (final l in legs) {
        expect(l.geometry, hasLength(2));
        expect(l.distanceMeters, greaterThan(0));
      }
    });

    test('飞行段永不贴合道路，也不在连续失败的计数里', () async {
      // 1 小时飞 900 公里 -> 900km/h，按速度反推是 fly
      final trip = makeTrip(3, perLeg: const Duration(hours: 1), metersPerLeg: 900000);
      final legs = await planStoryLegs(trip, AppSettings());

      expect(legs, hasLength(2));
      expect(legs.every((l) => l.mode == TravelMode2.flight), isTrue);
      expect(legs.every((l) => l.geometry.length >= 2), isTrue);
    });

    test('单站行程没有任何段，也不该抛', () async {
      final legs = await planStoryLegs(makeTrip(1), AppSettings());
      expect(legs, isEmpty);
    });

    test('段数与站点数无关地保持一致（20 站）', () async {
      final trip = makeTrip(20);
      final legs = await planStoryLegs(trip, AppSettings(routeProvider: 'direct'));
      expect(legs, hasLength(19));
      expect(legs.every((l) => l.geometry.length >= 2), isTrue);
    });
  });

  // 这一组是真正的端到端: 光有 legs 不够，还得能**接进 manifest 里的 routes**。
  // _stitchRoutes 按 `stop-N>stop-M` 查表，id 格式对不上就会静默丢弃 ——
  // 那等于白修。所以这里直接把整条链路跑通。
  group('端到端: legs 真的进了 manifest 的 routes', () {
    Map<String, PhotoRecord> recordsFor(TripRoute trip) => {
          for (final s in trip.stays)
            for (final pid in s.photoIds)
              pid: PhotoRecord(
                id: pid,
                takenAt: s.arrive,
                bytes: 1024,
                origFilename: '$pid.jpg',
                lat: s.lat,
                lon: s.lon,
              ),
        };

    Story buildStory(TripRoute trip, List<RouteLeg> legs) {
      final records = recordsFor(trip);
      return StoryBuilder.build(
        id: 's1',
        slug: 's1',
        title: '测试行程',
        trip: trip,
        recordsById: records,
        selectedIds: records.keys.toSet(),
        heroByStopSeq: const {},
        coverPhotoId: null,
        legs: legs,
        webPathOf: (r) => 'photos/${r.origFilename}',
      );
    }

    test('每一站都选了照片时，routes 段数 = 站点数 - 1', () async {
      final trip = makeTrip(4);
      final legs = await planStoryLegs(trip, AppSettings(routeProvider: 'direct'));
      final story = buildStory(trip, legs);

      expect(story.stops, hasLength(4));
      expect(story.routes, hasLength(3),
          reason: '这正是手机端发布时丢掉的东西: '
              'stops 有 4 个，routes 却是 0');
      for (final r in story.routes) {
        expect(r.encodedGeometry, isNotEmpty,
            reason: '${r.fromStopId}->${r.toStopId} 几何是空的，'
                '故事页上这一段会断掉');
      }
      // id 必须是 story 里真实的站 id，否则前端按 id 关联不上
      for (final r in story.routes) {
        expect(r.fromStopId, startsWith('stop-'));
        expect(r.toStopId, startsWith('stop-'));
      }
    });

    test('反证: 传空 legs 就一条路线都没有 —— 修复前手机端就是这个状态', () {
      final trip = makeTrip(4);
      final story = buildStory(trip, const []);

      expect(story.stops, hasLength(4),
          reason: '站点照常有，所以看上去"发布成功了"');
      expect(story.routes, isEmpty,
          reason: '但地图上一条线都没有 —— 这就是那个 bug 的样子');
    });
  });
}
