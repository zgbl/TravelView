import 'dart:io';

import 'package:test/test.dart';
import 'package:tv_core/tv_core.dart';

/// 假的供应商，用来在不联网的情况下验证编排逻辑
class FakeProvider implements RouteProvider {
  final bool fail;
  int calls = 0;
  FakeProvider({this.fail = false});

  @override
  String get name => 'fake';

  @override
  Future<RouteLeg?> route({
    required String fromStopId,
    required String toStopId,
    required LatLon from,
    required LatLon to,
    required TravelMode2 mode,
  }) async {
    calls++;
    if (fail) return null;
    // 造一条带很多冗余点的"道路"，顺便验证抽稀确实生效
    final pts = <LatLon>[];
    for (var i = 0; i <= 200; i++) {
      final t = i / 200;
      pts.add(LatLon(
        from.lat + (to.lat - from.lat) * t,
        from.lon + (to.lon - from.lon) * t,
      ));
    }
    return RouteLeg(
      fromStopId: fromStopId,
      toStopId: toStopId,
      mode: mode,
      source: RouteSource.inferred,
      provider: name,
      geometry: pts,
      distanceMeters: 12345,
      duration: const Duration(minutes: 30),
    );
  }
}

PhotoRecord ph(String id, DateTime t, double lat, double lon) => PhotoRecord(
      id: id,
      takenAt: t,
      bytes: 1,
      origFilename: id,
      lat: lat,
      lon: lon,
    );

void main() {
  final base = DateTime(2025, 9, 5, 9);

  TripRoute driveTrip() => buildRoute([
        ph('a', base, 37.7749, -122.4194),
        ph('a2', base.add(const Duration(minutes: 5)), 37.7750, -122.4195),
        ph('b', base.add(const Duration(hours: 5)), 36.1069, -112.1129),
        ph('b2', base.add(const Duration(hours: 5, minutes: 5)), 36.1070,
            -112.1130),
      ]);

  test('正常情况: 调用供应商并抽稀', () async {
    final fake = FakeProvider();
    final planner = RoutePlanner(provider: fake);
    final legs = await planner.planTrip(driveTrip());

    expect(legs.length, 1);
    expect(fake.calls, 1);
    expect(legs.single.provider, 'fake');
    expect(legs.single.geometry.length, lessThan(20),
        reason: '201 个点应该被抽稀掉大部分');
    expect(legs.single.geometry.first.lat, closeTo(37.775, 0.01));
  });

  test('供应商失败时退回直线，绝不空手而归', () async {
    final planner = RoutePlanner(provider: FakeProvider(fail: true));
    final legs = await planner.planTrip(driveTrip());

    expect(legs.length, 1);
    expect(legs.single.provider, 'direct');
    expect(legs.single.geometry.length, 2);
    expect(legs.single.distanceMeters, greaterThan(0));
  });

  test('飞行段不调用供应商，永远画直线', () async {
    final fake = FakeProvider();
    final trip = buildRoute([
      ph('a', base, 37.7749, -122.4194),
      ph('a2', base.add(const Duration(minutes: 5)), 37.7750, -122.4195),
      // 6 小时跨越美国 = 飞行
      ph('b', base.add(const Duration(hours: 6)), 40.7128, -74.0060),
      ph('b2', base.add(const Duration(hours: 6, minutes: 5)), 40.7129,
          -74.0061),
    ]);
    final legs = await RoutePlanner(provider: fake).planTrip(trip);

    expect(fake.calls, 0, reason: '飞行段不该去请求路径规划');
    expect(legs.single.mode, TravelMode2.flight);
    expect(legs.single.geometry.length, 2);
  });

  test('缓存命中就不再请求', () async {
    final dir = Directory.systemTemp.createTempSync('tv_route_');
    try {
      final cacheFile = File('${dir.path}/routes.json');
      final fake = FakeProvider();

      final cache1 = RouteCache(cacheFile);
      await cache1.load();
      await RoutePlanner(provider: fake, cache: cache1)
          .planTrip(driveTrip());
      expect(fake.calls, 1);
      expect(cache1.length, 1);
      expect(cacheFile.existsSync(), isTrue);

      // 新开一个缓存实例从磁盘读，模拟"关掉 App 再打开"
      final cache2 = RouteCache(cacheFile);
      await cache2.load();
      expect(cache2.length, 1);

      final fake2 = FakeProvider();
      final legs = await RoutePlanner(provider: fake2, cache: cache2)
          .planTrip(driveTrip());
      expect(fake2.calls, 0, reason: '算过的路线不该再打网络请求');
      expect(legs.single.provider, 'fake');
      expect(legs.single.geometry.length, greaterThan(1));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('退回直线的结果不进缓存，下次还有机会算出真路线', () async {
    final dir = Directory.systemTemp.createTempSync('tv_route2_');
    try {
      final cache = RouteCache(File('${dir.path}/routes.json'));
      await cache.load();
      await RoutePlanner(provider: FakeProvider(fail: true), cache: cache)
          .planTrip(driveTrip());
      expect(cache.length, 0, reason: '兜底的直线不该被当成算好的路线存起来');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('缓存键按坐标取整，微小抖动仍能命中', () {
    const a = LatLon(37.774900, -122.419400);
    const b = LatLon(37.774903, -122.419402);
    const c = LatLon(36.1069, -112.1129);
    expect(RouteCache.keyFor(a, c, TravelMode2.driving),
        RouteCache.keyFor(b, c, TravelMode2.driving));
    expect(RouteCache.keyFor(a, c, TravelMode2.driving),
        isNot(RouteCache.keyFor(a, c, TravelMode2.walking)));
  });

  test('进度回调逐段上报', () async {
    final trip = buildRoute([
      ph('a', base, 37.0, -122.0),
      ph('a2', base.add(const Duration(minutes: 5)), 37.001, -122.001),
      ph('b', base.add(const Duration(hours: 3)), 36.0, -120.0),
      ph('b2', base.add(const Duration(hours: 3, minutes: 5)), 36.001, -120.001),
      ph('c', base.add(const Duration(hours: 6)), 35.0, -118.0),
      ph('c2', base.add(const Duration(hours: 6, minutes: 5)), 35.001, -118.001),
    ]);
    final seen = <int>[];
    await RoutePlanner(provider: FakeProvider())
        .planTrip(trip, onProgress: (d, t) => seen.add(d));
    expect(seen, [1, 2]);
  });
}
