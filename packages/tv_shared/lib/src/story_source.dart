import 'package:tv_core/tv_core.dart';

/// Story 导出时，"照片从哪来"这件事的抽象。
///
/// 桌面端的照片在一个真实的照片库目录里，靠 `Catalog` 查到相对路径；
/// 手机端的照片在系统相册里，**根本没有稳定的文件路径**，只有资产 id。
/// 导出逻辑（挑哪些、缩多大、写什么 manifest）两端完全一样，
/// 不一样的只有这两件事，所以只把这两件事抽出来。
///
/// [sourceOf] 返回的字符串会**原样交给 [ImageOps.exportWeb]**：
/// 桌面端那份实现认文件路径，手机端那份认资产 id。
/// 导出器不需要知道它拿到的是哪一种。
abstract class StorySource {
  PhotoRecord? byId(String id);

  /// 找不到（文件被用户删了、资产已从相册移除）返回 null，
  /// 导出器会记一条 warning 然后跳过这张 —— **不中断整篇导出**。
  String? sourceOf(String id);
}
