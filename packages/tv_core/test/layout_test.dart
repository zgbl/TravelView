import 'package:test/test.dart';
import 'package:tv_core/tv_core.dart';

void main() {
  group('LibraryLayout', () {
    test('目录和文件名按时间可排序', () {
      final t = DateTime(2025, 9, 12, 14, 30, 22);
      expect(LibraryLayout.dayDirRelative(t), 'photos/2025/2025-09-12');
      expect(LibraryLayout.fileName(t, 'IMG_1234.HEIC'),
          '2025-09-12 14-30-22 IMG_1234.HEIC');
    });

    test('清掉 exFAT 上的非法字符', () {
      expect(LibraryLayout.sanitize('a/b:c*d?.jpg'), 'a_b_c_d_.jpg');
      expect(LibraryLayout.sanitize('  x   y  .jpg'), 'x y .jpg');
      expect(LibraryLayout.sanitize('trailing...'), 'trailing');
      expect(LibraryLayout.sanitize(''), 'unnamed');
    });

    test('冲突后缀由内容 id 决定，与导入顺序无关', () {
      final t = DateTime(2025, 9, 12, 14, 30, 22);
      final a = LibraryLayout.fileNameWithSuffix(t, 'IMG_1.JPG', 'abcdef0123456789');
      final b = LibraryLayout.fileNameWithSuffix(t, 'IMG_1.JPG', 'abcdef0123456789');
      expect(a, b);
      expect(a, endsWith('~abcdef.JPG'));
    });

    test('超长文件名被截断但保留扩展名', () {
      final long = '${'x' * 300}.HEIC';
      final s = LibraryLayout.sanitize(long);
      expect(s.length, lessThanOrEqualTo(180));
      expect(s, endsWith('.HEIC'));
    });
  });
}
