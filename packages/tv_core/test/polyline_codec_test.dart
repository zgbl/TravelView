import 'package:test/test.dart';
import 'package:tv_core/tv_core.dart';

void main() {
  group('Polyline 编解码', () {
    test('往返一致（precision 6）', () {
      const pts = [
        LatLon(38.5, -120.2),
        LatLon(40.7, -120.95),
        LatLon(43.252, -126.453),
      ];
      final enc = PolylineCodec.encode(pts);
      final back = PolylineCodec.decode(enc);
      expect(back.length, 3);
      for (var i = 0; i < pts.length; i++) {
        expect(back[i].lat, closeTo(pts[i].lat, 1e-6));
        expect(back[i].lon, closeTo(pts[i].lon, 1e-6));
      }
    });

    test('precision 5 也能往返', () {
      const pts = [LatLon(38.5, -120.2), LatLon(40.7, -120.95)];
      final back = PolylineCodec.decode(
          PolylineCodec.encode(pts, precision: 5),
          precision: 5);
      expect(back.first.lat, closeTo(38.5, 1e-5));
      expect(back.last.lon, closeTo(-120.95, 1e-5));
    });

    test('比 GeoJSON 数字数组小得多', () {
      // 造一条一万点的洲际路线
      final pts = <LatLon>[];
      for (var i = 0; i < 10000; i++) {
        pts.add(LatLon(37.0 + i * 0.0003, -122.0 + i * 0.0005));
      }
      final encoded = PolylineCodec.encode(pts);
      // GeoJSON 里每个点大约 "[-122.1234567,37.1234567]," 这么长
      final geoJsonApprox = pts.length * 26;
      expect(encoded.length, lessThan(geoJsonApprox ~/ 3),
          reason: 'manifest 体积决定分享页在手机上的打开速度');
    });

    test('负坐标和跨零点正确', () {
      const pts = [
        LatLon(-33.8688, 151.2093),
        LatLon(0.0, 0.0),
        LatLon(51.5074, -0.1278),
      ];
      final back = PolylineCodec.decode(PolylineCodec.encode(pts));
      expect(back[0].lat, closeTo(-33.8688, 1e-6));
      expect(back[1].lat, closeTo(0, 1e-6));
      expect(back[2].lon, closeTo(-0.1278, 1e-6));
    });

    test('空输入不崩', () {
      expect(PolylineCodec.encode(const []), '');
      expect(PolylineCodec.decode(''), isEmpty);
    });

    test('坏数据不崩，能解多少算多少', () {
      expect(() => PolylineCodec.decode('~~~invalid~~~'), returnsNormally);
    });
  });
}
