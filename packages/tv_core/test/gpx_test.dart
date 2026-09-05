import 'package:test/test.dart';
import 'package:tv_core/tv_core.dart';

void main() {
  final leg = RouteLeg(
    fromStopId: 'a',
    toStopId: 'b',
    mode: TravelMode2.driving,
    source: RouteSource.inferred,
    provider: 'osrm',
    distanceMeters: 1000,
    geometry: const [
      LatLon(35.6762, 139.6503),
      LatLon(35.45, 139.4),
      LatLon(35.2323, 139.1069),
    ],
  );

  test('导出的 GPX 结构完整', () {
    final xml = Gpx.write(
      tripName: '横穿美国 2025',
      waypoints: [
        GpxWaypoint(
            point: const LatLon(35.6762, 139.6503),
            name: 'Tokyo',
            time: DateTime.utc(2025, 10, 3, 9)),
      ],
      legs: [leg],
    );
    expect(xml, contains('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(xml, contains('creator="TravelView"'));
    expect(xml, contains('<wpt lat="35.6762" lon="139.6503">'));
    expect(xml, contains('<name>Tokyo</name>'));
    expect(xml, contains('<trkseg>'));
    expect(xml, contains('<trkpt lat="35.45" lon="139.4">'));
    expect(xml, contains('</gpx>'));
  });

  test('特殊字符会被转义，不会写出坏 XML', () {
    final xml = Gpx.write(
      tripName: 'Tom & Jerry <trip>',
      waypoints: const [],
      legs: const [],
    );
    expect(xml, contains('Tom &amp; Jerry &lt;trip&gt;'));
    expect(xml, isNot(contains('<trip>')));
  });

  test('导出再读回来，点位一致', () {
    final xml = Gpx.write(tripName: 't', waypoints: const [], legs: [leg]);
    final pts = Gpx.readTrackPoints(xml);
    expect(pts.length, 3);
    expect(pts.first.lat, closeTo(35.6762, 1e-6));
    expect(pts.last.lon, closeTo(139.1069, 1e-6));
  });

  test('能读 lon 写在前面的 GPX', () {
    const xml = '''
<gpx><trk><trkseg>
<trkpt lon="139.1" lat="35.2"></trkpt>
<trkpt lon="139.2" lat="35.3"></trkpt>
</trkseg></trk></gpx>''';
    final pts = Gpx.readTrackPoints(xml);
    expect(pts.length, 2);
    expect(pts.first.lat, 35.2);
    expect(pts.first.lon, 139.1);
  });

  test('读进来的轨迹可以抽稀后直接当作 actual 路线', () {
    final dense = <LatLon>[];
    for (var i = 0; i < 2000; i++) {
      dense.add(LatLon(35 + i * 0.0001, 139 + i * 0.0001));
    }
    final xml = Gpx.write(
      tripName: 't',
      waypoints: const [],
      legs: [
        RouteLeg(
          fromStopId: 'a',
          toStopId: 'b',
          mode: TravelMode2.driving,
          source: RouteSource.actual,
          provider: 'gpx',
          distanceMeters: 0,
          geometry: dense,
        )
      ],
    );
    final back = Gpx.readTrackPoints(xml);
    expect(back.length, 2000);
    final simplified = RoutePath.simplify(back, toleranceMeters: 10);
    expect(simplified.length, lessThan(100));
  });

  test('空 GPX 不崩', () {
    expect(Gpx.readTrackPoints('<gpx></gpx>'), isEmpty);
    expect(Gpx.readTrackPoints(''), isEmpty);
  });
}
