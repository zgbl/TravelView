import 'package:test/test.dart';
import 'package:tv_core/tv_core.dart';

/// 造一趟自驾：多数站挨得很近（路上随手拍），中间几处有长空档。
TripRoute _fake({int stops = 53}) {
  var t = DateTime(2025, 9, 8, 9);
  final photos = <PhotoRecord>[];
  for (var i = 0; i < stops; i++) {
    // 每站两张，位置一路往东挪
    for (var k = 0; k < 2; k++) {
      photos.add(PhotoRecord(
        id: 's${i}_$k',
        bytes: 1000,
        origFilename: 's${i}_$k.jpg',
        takenAt: t.add(Duration(minutes: k * 3)),
        lat: 35.0,
        lon: -106.0 + i * 0.3,
      ));
    }
    // 过夜放在中间
    t = t.add(Duration(minutes: i == 26 ? 9 * 60 : 40));
  }
  return buildRoute(photos);
}

void main() {
  test('合并只减段数，不丢地理点', () {
    final fine = _fake();
    final ch = mergeIntoChapters(fine);

    expect(fine.stays.length, greaterThan(20), reason: '样本本身应该是碎的');
    expect(ch.stays.length, lessThan(fine.stays.length));
    expect(ch.stays.length, lessThanOrEqualTo(16));

    // 照片一张都不能少，顺序也不能乱
    final before = [for (final s in fine.stays) ...s.photoIds];
    final after = [for (final s in ch.stays) ...s.photoIds];
    expect(after, before);

    // 轨迹点用的是合并前那份
    expect(routePath(fine).length, fine.stays.length);
  });

  test('距离沿原始站点累加，不因合并而变短', () {
    final fine = _fake();
    final ch = mergeIntoChapters(fine);
    // 允许一点点误差：章内部最后一段到下一章起点的算法一致，
    // 总长应当基本相等
    expect((ch.totalKm - fine.totalKm).abs(), lessThan(fine.totalKm * 0.02));
  });

  test('用户指定几段就是几段', () {
    final fine = _fake();
    expect(mergeIntoChapters(fine, target: 5).stays.length, 5);
    expect(mergeIntoChapters(fine, target: 12).stays.length, 12);
  });

  test('站点本来就少时原样返回', () {
    final fine = _fake(stops: 3);
    expect(mergeIntoChapters(fine).stays.length, fine.stays.length);
  });
}
