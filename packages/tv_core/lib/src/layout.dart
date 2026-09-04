import 'package:path/path.dart' as p;

/// 磁盘布局规则。
///
/// 目标是"在任何文件管理器里按名字排序就等于按时间排序"，
/// 不依赖 mtime（复制会丢），也不依赖任何 App。
class LibraryLayout {
  /// 库根目录下的固定子目录名
  static const photosDir = 'photos';
  static const viewsDir = 'views';
  static const catalogDir = 'catalog';
  static const sidecarName = '.tvmeta.json';
  static const catalogJsonl = 'catalog.jsonl';
  static const readmeName = 'TRAVELVIEW.md';

  /// photos/2025/2025-09-12
  static String dayDirRelative(DateTime t) =>
      p.join(photosDir, '${t.year}', dateStamp(t));

  /// 2025-09-12
  static String dateStamp(DateTime t) =>
      '${t.year}-${_p2(t.month)}-${_p2(t.day)}';

  /// 14-30-22
  static String timeStamp(DateTime t) =>
      '${_p2(t.hour)}-${_p2(t.minute)}-${_p2(t.second)}';

  /// 2025-09-12 14-30-22 IMG_1234.HEIC
  static String fileName(DateTime t, String origFilename) =>
      '${dateStamp(t)} ${timeStamp(t)} ${sanitize(origFilename)}';

  /// 冲突时追加内容 id 前 6 位，而不是 (1)(2) —— 保证可推导、不随导入顺序变化。
  static String fileNameWithSuffix(
      DateTime t, String origFilename, String contentId) {
    final base = sanitize(origFilename);
    final ext = p.extension(base);
    final stem = base.substring(0, base.length - ext.length);
    return '${dateStamp(t)} ${timeStamp(t)} $stem~${contentId.substring(0, 6)}$ext';
  }

  /// 清掉在 exFAT / NTFS 上非法或会引起麻烦的字符。
  /// 移动硬盘多为 exFAT，所以按最严格的那个来。
  static String sanitize(String name) {
    var s = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    while (s.endsWith('.')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) s = 'unnamed';
    // exFAT 单个文件名上限 255 个 UTF-16 码元，留足余量
    if (s.length > 180) {
      final ext = p.extension(s);
      s = s.substring(0, 180 - ext.length) + ext;
    }
    return s;
  }

  /// 视图目录名，例如 "2025-09-12 京都·大阪 8天"
  static String tripDirName(DateTime start, String title) =>
      sanitize('${dateStamp(start)} $title');

  static String _p2(int n) => n.toString().padLeft(2, '0');
}
