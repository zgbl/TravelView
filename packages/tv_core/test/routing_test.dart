import 'package:test/test.dart';
import 'package:tv_core/tv_core.dart';

void main() {
  group('GeoJSON 坐标顺序', () {
    test('存的是 [经度, 纬度]，不能反', () {
      const p = LatLon(35.0, 135.0);
      expect(p.toGeoJson(), [135.0, 35.0]);
      final back = LatLon.fromGeoJson(p.toGeoJson());
      expect(back.lat, 35.0);
      expect(back.lon, 135.0);
    });
  });

  group('直线供应商', () {
    test('永远能出结果，不联网', () async {
      const provider = DirectRouteProvider();
      final leg = await provider.route(
        fromStopId: 'a',
        toStopId: 'b',
        from: const LatLon(37.7749, -122.4194),
        to: const LatLon(34.0522, -118.2437),
        mode: TravelMode2.driving,
      );
      expect(leg, isNotNull);
      expect(leg!.geometry.length, 2);
      expect(leg.distanceMeters / 1000, closeTo(559, 20));
      expect(leg.source, RouteSource.inferred);
    });
  });

  group('RouteLeg 序列化', () {
    test('存下来再读回来内容一致', () {
      final leg = RouteLeg(
        fromStopId: 'tokyo',
        toStopId: 'hakone',
        mode: TravelMode2.driving,
        source: RouteSource.inferred,
        provider: 'osrm',
        distanceMeters: 102340,
        duration: const Duration(hours: 2),
        geometry: const [
          LatLon(35.6762, 139.6503),
          LatLon(35.45, 139.4),
          LatLon(35.2323, 139.1069),
        ],
      );
      final back = RouteLeg.fromJson(leg.toJson());
      expect(back.fromStopId, 'tokyo');
      expect(back.mode, TravelMode2.driving);
      expect(back.source, RouteSource.inferred);
      expect(back.provider, 'osrm');
      expect(back.distanceMeters, 102340);
      expect(back.duration, const Duration(hours: 2));
      expect(back.geometry.length, 3);
      expect(back.geometry[1].lat, 35.45);
    });

    test('geometry 是标准 GeoJSON LineString', () {
      const leg = RouteLeg(
        fromStopId: 'a',
        toStopId: 'b',
        mode: TravelMode2.walking,
        source: RouteSource.reconstructed,
        provider: 'osrm',
        distanceMeters: 100,
        geometry: [LatLon(1, 2), LatLon(3, 4)],
      );
      final j = leg.toJson();
      expect((j['geometry'] as Map)['type'], 'LineString');
      expect((j['geometry'] as Map)['coordinates'], [
        [2.0, 1.0],
        [4.0, 3.0],
      ]);
    });
  });

  group('折线几何（小车动画的基础）', () {
    // 沿赤道向东的一条直线，方便验算
    final line = RoutePath(const [
      LatLon(0, 0),
      LatLon(0, 1),
      LatLon(0, 2),
      LatLon(0, 3),
    ]);

    test('累计距离递增，首项为 0', () {
      expect(line.cumulative.first, 0);
      for (var i = 1; i < line.cumulative.length; i++) {
        expect(line.cumulative[i], greaterThan(line.cumulative[i - 1]));
      }
    });

    test('进度 0 和 1 落在两端', () {
      expect(line.positionAt(0)!.lon, closeTo(0, 0.001));
      expect(line.positionAt(1)!.lon, closeTo(3, 0.001));
    });

    test('进度一半落在中点', () {
      expect(line.positionAt(0.5)!.lon, closeTo(1.5, 0.01));
    });

    test('方向: 一路向东是 90 度', () {
      expect(line.bearingAt(0.3), closeTo(90, 1));
    });

    test('方向: 向北是 0 度', () {
      final north = RoutePath(const [LatLon(0, 0), LatLon(1, 0)]);
      expect(north.bearingAt(0.5), closeTo(0, 1));
    });

    test('走过的那一段随进度变长', () {
      final quarter = line.traveled(0.25);
      final most = line.traveled(0.9);
      expect(quarter.length, lessThan(most.length));
      expect(line.traveled(1).length, line.points.length);
      expect(quarter.first.lon, 0);
    });

    test('单点和空线不崩', () {
      expect(RoutePath(const []).positionAt(0.5), isNull);
      expect(RoutePath(const [LatLon(1, 1)]).positionAt(0.5)?.lat, 1);
      expect(RoutePath(const []).totalMeters, 0);
    });
  });

  group('抽稀', () {
    test('直线上的中间点会被去掉', () {
      final pts = [
        for (var i = 0; i <= 100; i++) LatLon(0, i * 0.001),
      ];
      final simplified = RoutePath.simplify(pts, toleranceMeters: 10);
      expect(simplified.length, lessThan(10));
      expect(simplified.first.lon, 0);
      expect(simplified.last.lon, closeTo(0.1, 1e-9));
    });

    test('拐弯处必须保留', () {
      final pts = const [
        LatLon(0, 0),
        LatLon(0, 0.01),
        LatLon(0.01, 0.01), // 直角拐弯
        LatLon(0.02, 0.01),
      ];
      final simplified = RoutePath.simplify(pts, toleranceMeters: 10);
      expect(simplified.length, greaterThanOrEqualTo(3),
          reason: '拐点丢了路线形状就错了');
    });

    test('两个点以内原样返回', () {
      expect(RoutePath.simplify(const [LatLon(0, 0)]).length, 1);
      expect(RoutePath.simplify(const [LatLon(0, 0), LatLon(1, 1)]).length, 2);
    });

    test('抽稀能显著压缩洲际路线的点数', () {
      // 模拟一条带噪声的长路线
      final pts = <LatLon>[];
      for (var i = 0; i < 5000; i++) {
        final jitter = (i % 7) * 0.000002;
        pts.add(LatLon(37 + i * 0.0002 + jitter, -122 + i * 0.0004));
      }
      final simplified = RoutePath.simplify(pts, toleranceMeters: 10);
      expect(simplified.length, lessThan(pts.length ~/ 10),
          reason: 'manifest 体积直接决定分享页在手机上的打开速度');
    });
  });

  group('站的进出口', () {
    test('用最早/最晚照片的位置，而不是簇中心', () {
      final photos = [
        PhotoRecord(
            id: 'a',
            takenAt: DateTime(2025, 9, 5, 9),
            bytes: 1,
            origFilename: 'a',
            lat: 35.7000,
            lon: 139.7000),
        PhotoRecord(
            id: 'b',
            takenAt: DateTime(2025, 9, 5, 9, 20),
            bytes: 1,
            origFilename: 'b',
            lat: 35.7010,
            lon: 139.7010),
        PhotoRecord(
            id: 'c',
            takenAt: DateTime(2025, 9, 5, 9, 40),
            bytes: 1,
            origFilename: 'c',
            lat: 35.7020,
            lon: 139.7020),
      ];
      final r = buildRoute(photos, options: ClusterOptions.city);
      final stop = r.stays.single;
      expect(stop.routeEntryLat, 35.7000, reason: '入口是最早那张照片的位置');
      expect(stop.routeExitLat, 35.7020, reason: '出口是最晚那张照片的位置');
      expect(stop.lat, isNot(stop.routeEntryLat), reason: '中心点不等于进出口');
    });
  });
}
