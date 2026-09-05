import 'package:test/test.dart';
import 'package:tv_core/tv_core.dart';

PhotoRecord ph(
  String id,
  DateTime t, {
  double? sharp,
  String? phash,
  int? faces,
  int w = 4032,
  int h = 3024,
  bool screenshot = false,
  double? brightness,
  List<Tag> tags = const [],
}) =>
    PhotoRecord(
      id: id,
      takenAt: t,
      bytes: 1000,
      origFilename: '$id.HEIC',
      width: w,
      height: h,
      sharpness: sharp,
      phash: phash,
      faceCount: faces,
      brightness: brightness,
      isScreenshot: screenshot,
      tags: tags,
    );

Stop stopOf(List<PhotoRecord> ps) => Stop(
      seq: 0,
      lat: 35,
      lon: 135,
      arrive: ps.first.takenAt,
      leave: ps.last.takenAt,
      photoIds: ps.map((e) => e.id).toList(),
    );

/// 生成一个**彼此差别足够大**的假感知哈希。
/// 直接用 0000..000N 那种只差一位的字符串，汉明距离只有 1-3，
/// 会被判成同一张 —— 那测的就不是精选逻辑了。
String _hash(int seed) {
  const alphabet = '0123456789abcdef';
  final b = StringBuffer();
  for (var i = 0; i < 16; i++) {
    b.write(alphabet[(seed * 7 + i * 11 + (seed >> 2)) % 16]);
  }
  return b.toString();
}

void main() {
  final base = DateTime(2025, 9, 5, 10, 0);
  const curator = Curator();

  group('感知哈希距离', () {
    test('完全相同为 0', () {
      expect(hammingDistance('ffffffffffffffff', 'ffffffffffffffff'), 0);
    });
    test('一位之差为 1', () {
      expect(hammingDistance('0000000000000000', '0000000000000001'), 1);
    });
    test('长度不同视为完全不同', () {
      expect(hammingDistance('ff', 'ffff'), 64);
    });
  });

  group('打分', () {
    test('截图会被大幅扣分', () {
      final photos = [
        ph('a', base, sharp: 100),
        ph('shot', base, sharp: 100, screenshot: true, w: 1170, h: 2532),
      ];
      final scored = curator.score(photos);
      final shot = scored.firstWhere((s) => s.photo.id == 'shot');
      final normal = scored.firstWhere((s) => s.photo.id == 'a');
      expect(shot.total, lessThan(normal.total));
      expect(shot.breakdown['截图'], lessThan(0));
    });

    test('手动选取过的分数最高，自动精选不该跟用户对着干', () {
      final photos = [
        ph('blurry', base, sharp: 1, tags: [const Tag('pick', '精选')]),
        ph('sharp', base.add(const Duration(hours: 1)), sharp: 999),
      ];
      final scored = curator.score(photos);
      final picked = scored.firstWhere((s) => s.photo.id == 'blurry');
      expect(picked.breakdown['已手选'], greaterThan(0));
      expect(picked.total, greaterThan(
          scored.firstWhere((s) => s.photo.id == 'sharp').total));
    });

    test('有人脸会加分', () {
      final scored = curator.score([
        ph('faces', base, faces: 2),
        ph('none', base.add(const Duration(minutes: 5))),
      ]);
      expect(scored.first.breakdown['有人'], greaterThan(0));
    });

    test('理由可以给用户看', () {
      final scored = curator.score([ph('a', base, sharp: 100, faces: 1)]);
      expect(scored.single.breakdown, isNotEmpty);
      expect(scored.single.topReason, isNotEmpty);
    });
  });

  group('去重', () {
    test('连拍的一串被并成一组', () {
      // 同一个自拍连按 5 下: 哈希几乎一样、时间只差几秒
      final photos = [
        for (var i = 0; i < 5; i++)
          ph('burst$i', base.add(Duration(seconds: i * 2)),
              phash: 'aaaaaaaaaaaaaaa${i}', sharp: 50.0 + i),
      ];
      final groups = curator.groupDuplicates(curator.score(photos));
      expect(groups.length, 1, reason: '连拍应该只算一组');
      expect(groups.single.length, 5);
    });

    test('组内保留分数最高的那张', () {
      final photos = [
        ph('dull', base, phash: 'aaaaaaaaaaaaaaaa', sharp: 10),
        ph('crisp', base.add(const Duration(seconds: 3)),
            phash: 'aaaaaaaaaaaaaaab', sharp: 900),
      ];
      final groups = curator.groupDuplicates(curator.score(photos));
      expect(groups.single.best.photo.id, 'crisp');
    });

    test('不同景物不会被误并', () {
      final photos = [
        ph('street', base, phash: '0000000000000000'),
        ph('food', base.add(const Duration(minutes: 30)),
            phash: 'ffffffffffffffff'),
      ];
      final groups = curator.groupDuplicates(curator.score(photos));
      expect(groups.length, 2);
    });

    test('没有哈希时靠时间兜底: 十几秒内的算连拍', () {
      final photos = [
        ph('a', base),
        ph('b', base.add(const Duration(seconds: 1))),
      ];
      final groups = curator.groupDuplicates(curator.score(photos));
      expect(groups.length, 1, reason: '信号还没算出来时也要能去掉连拍');
    });

    test('没有哈希且时间隔得远时不并组', () {
      final photos = [
        ph('a', base),
        ph('b', base.add(const Duration(minutes: 5))),
      ];
      final groups = curator.groupDuplicates(curator.score(photos));
      expect(groups.length, 2);
    });
  });

  group('一站的精选', () {
    test('91 张压到十张以内，且优先来自不同的组', () {
      // 模拟真实的一天: 5 个场景，每个场景连拍一堆
      final photos = <PhotoRecord>[];
      for (var scene = 0; scene < 5; scene++) {
        for (var i = 0; i < 18; i++) {
          photos.add(ph(
            's${scene}_$i',
            base.add(Duration(minutes: scene * 45, seconds: i * 3)),
            phash: _hash(scene * 4 + (i ~/ 6)),
            sharp: 100.0 + i,
          ));
        }
      }
      expect(photos.length, 90);

      final sel = curator.curateStop(stopOf(photos), photos);
      expect(sel.totalPhotos, 90);
      expect(sel.selected.length, lessThanOrEqualTo(10));
      expect(sel.selected.length, greaterThanOrEqualTo(3));
      expect(sel.duplicatesRemoved, greaterThan(60),
          reason: '大部分连拍应该被折叠掉');
      // 选出来的照片彼此的拍摄时间不该挤在一起
      final times = sel.selected.map((e) => e.takenAt).toList();
      expect(times.last.difference(times.first).inMinutes, greaterThan(30));
    });

    test('照片很少时全部保留', () {
      final photos = [
        ph('a', base, phash: '0000000000000000'),
        ph('b', base.add(const Duration(minutes: 20)), phash: 'ffffffffffffffff'),
      ];
      final sel = curator.curateStop(stopOf(photos), photos);
      expect(sel.selected.length, 2);
    });

    test('封面优先横构图', () {
      final photos = [
        ph('portrait', base, sharp: 500, w: 3024, h: 4032,
            phash: '0000000000000000'),
        ph('landscape', base.add(const Duration(minutes: 20)), sharp: 480,
            w: 4032, h: 3024, phash: 'ffffffffffffffff'),
      ];
      final sel = curator.curateStop(stopOf(photos), photos);
      expect(sel.hero?.id, 'landscape');
    });

    test('可以指定张数', () {
      final photos = [
        for (var i = 0; i < 20; i++)
          ph('p$i', base.add(Duration(minutes: i * 7)),
              phash: _hash(i), sharp: 100.0 + i),
      ];
      const c = Curator(options: CurationOptions(targetCount: 4));
      final sel = c.curateStop(stopOf(photos), photos);
      expect(sel.selected.length, 4);
    });

    test('空输入不崩', () {
      final s = Stop(
          seq: 0,
          lat: 0,
          lon: 0,
          arrive: base,
          leave: base,
          photoIds: const []);
      final sel = curator.curateStop(s, const []);
      expect(sel.selected, isEmpty);
      expect(sel.hero, isNull);
    });
  });
}
