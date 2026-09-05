import 'package:test/test.dart';
import 'package:tv_core/tv_core.dart';

PhotoRecord ph(String id, DateTime t, double lat, double lon) => PhotoRecord(
      id: id,
      takenAt: t,
      bytes: 1,
      origFilename: '$id.HEIC',
      lat: lat,
      lon: lon,
    );

void main() {
  group('haversine', () {
    test('旧金山到纽约约 4130 公里', () {
      final m = haversineMeters(37.7749, -122.4194, 40.7128, -74.0060);
      expect(m / 1000, closeTo(4130, 40));
    });

    test('同一点距离为 0', () {
      expect(haversineMeters(35.0, 135.0, 35.0, 135.0), closeTo(0, 0.001));
    });
  });

  group('站点聚类', () {
    test('同一地点的连续照片合成一个节点', () {
      final base = DateTime(2025, 9, 12, 9, 0);
      final photos = [
        ph('a', base, 36.9147, -111.4558),
        ph('b', base.add(const Duration(minutes: 5)), 36.9150, -111.4560),
        ph('c', base.add(const Duration(minutes: 12)), 36.9145, -111.4555),
      ];
      final r = buildRoute(photos);
      expect(r.stays.length, 1);
      expect(r.stays.first.photoCount, 3);
      expect(r.stays.first.duration.inMinutes, 12);
    });

    test('走远了就切成两个节点', () {
      final base = DateTime(2025, 9, 12, 9, 0);
      final photos = [
        ph('a', base, 36.9147, -111.4558),
        ph('b', base.add(const Duration(minutes: 20)), 36.9147, -111.4558),
        // 约 90 公里外
        ph('c', base.add(const Duration(hours: 2)), 36.1069, -112.1129),
        ph('d', base.add(const Duration(hours: 2, minutes: 10)), 36.1070, -112.1130),
      ];
      final r = buildRoute(photos);
      expect(r.stays.length, 2);
      expect(r.legs.length, 1);
      expect(r.legs.first.meters / 1000, closeTo(105, 20));
    });

    test('同一地点但隔了一夜，切成两个节点', () {
      final photos = [
        ph('a', DateTime(2025, 9, 12, 18, 0), 36.9147, -111.4558),
        ph('b', DateTime(2025, 9, 13, 8, 0), 36.9147, -111.4558),
      ];
      final r = buildRoute(photos);
      expect(r.stays.length, 2, reason: '时间断裂也要切，否则一个营地会算成一次停留');
    });

    test('没有 GPS 的照片被忽略，不影响路线', () {
      final base = DateTime(2025, 9, 12, 9, 0);
      final photos = [
        ph('a', base, 36.9147, -111.4558),
        PhotoRecord(
            id: 'noloc',
            takenAt: base.add(const Duration(minutes: 1)),
            bytes: 1,
            origFilename: 'screenshot.PNG'),
        ph('b', base.add(const Duration(minutes: 2)), 36.9148, -111.4559),
      ];
      final r = buildRoute(photos);
      expect(r.stays.length, 1);
      expect(r.stays.first.photoCount, 2);
    });

    test('空输入不崩', () {
      expect(buildRoute(const <PhotoRecord>[]).isEmpty, isTrue);
    });
  });

  group('交通方式推断', () {
    test('飞行段: 长距离短时间', () {
      final photos = [
        ph('a', DateTime(2025, 9, 12, 8, 0), 37.7749, -122.4194), // SFO
        ph('b', DateTime(2025, 9, 12, 14, 0), 40.7128, -74.0060), // NYC
      ];
      final r = buildRoute(photos);
      expect(r.legs.single.mode, TravelMode.fly);
    });

    test('自驾段: 中距离数小时', () {
      final photos = [
        ph('a', DateTime(2025, 9, 12, 8, 0), 36.9147, -111.4558),
        ph('b', DateTime(2025, 9, 12, 11, 0), 36.1069, -112.1129),
      ];
      final r = buildRoute(photos);
      expect(r.legs.single.mode, TravelMode.drive);
    });

    test('步行段: 短距离', () {
      final photos = [
        ph('a', DateTime(2025, 9, 12, 8, 0), 36.9147, -111.4558),
        ph('b', DateTime(2025, 9, 12, 9, 0), 36.9350, -111.4558),
      ];
      final r = buildRoute(photos);
      expect(r.legs.single.mode, TravelMode.walk);
    });
  });

  group('行程统计', () {
    test('总里程与天数', () {
      final photos = [
        ph('a', DateTime(2025, 9, 12, 9, 0), 37.7749, -122.4194),
        ph('b', DateTime(2025, 9, 13, 9, 0), 36.1069, -112.1129),
        ph('c', DateTime(2025, 9, 14, 9, 0), 39.7392, -104.9903),
      ];
      final r = buildRoute(photos);
      expect(r.stays.length, 3);
      expect(r.dayCount, 3);
      expect(r.totalKm, greaterThan(1000));
      expect(r.totalMiles, lessThan(r.totalKm));
      expect(r.byDay.keys, containsAll(['2025-09-12', '2025-09-13', '2025-09-14']));
    });
  });

  group('长途自驾预设', () {
    test('minPhotos 会把路上随手拍的碎片合并掉', () {
      final base = DateTime(2025, 9, 12, 8, 0);
      final photos = [
        ph('a1', base, 36.9147, -111.4558),
        ph('a2', base.add(const Duration(minutes: 3)), 36.9148, -111.4559),
        ph('a3', base.add(const Duration(minutes: 6)), 36.9149, -111.4560),
        // 路上随手拍一张，单独成簇
        ph('solo', base.add(const Duration(hours: 3)), 36.5000, -111.8000),
        ph('b1', base.add(const Duration(hours: 6)), 36.1069, -112.1129),
        ph('b2', base.add(const Duration(hours: 6, minutes: 5)), 36.1070, -112.1130),
        ph('b3', base.add(const Duration(hours: 6, minutes: 9)), 36.1071, -112.1131),
      ];
      final loose = buildRoute(photos);
      final tight = buildRoute(photos, options: ClusterOptions.roadTrip);
      expect(loose.stays.length, 3);
      expect(tight.stays.length, lessThan(loose.stays.length),
          reason: '长途预设应把单张碎片并进邻居');
      expect(
        tight.stays.fold<int>(0, (a, s) => a + s.photoCount),
        photos.length,
        reason: '合并不能丢照片',
      );
    });
  });
}
