import 'l10n.dart';

/// 一张导出用的派生图。
class ExportedImage {
  final String path;
  final String format;
  final int width;
  final int height;
  final int bytes;
  const ExportedImage({
    required this.path,
    required this.format,
    required this.width,
    required this.height,
    required this.bytes,
  });
}

/// 自动精选要用的图像信号。
class PhotoSignals {
  final double? sharpness;
  final double? brightness;
  final String? phash;
  final int? faceCount;
  const PhotoSignals({
    this.sharpness,
    this.brightness,
    this.phash,
    this.faceCount,
  });
}

/// 照片的 EXIF 元数据。macOS 走 ImageIO，iOS / Android 走各自的系统解码器，
/// 都原生支持 HEIC。
class PhotoMeta {
  final DateTime? takenAt;
  final double? lat;
  final double? lon;
  final int? width;
  final int? height;
  final String? device;

  const PhotoMeta({
    this.takenAt,
    this.lat,
    this.lon,
    this.width,
    this.height,
    this.device,
  });

  bool get isEmpty => takenAt == null && lat == null && width == null;

  /// EXIF 的时间格式是 "2025:09:12 14:30:22"，不是 ISO8601。
  static DateTime? parseExifDate(String? s) {
    if (s == null || s.length < 19) return null;
    final d = s.substring(0, 10).replaceAll(':', '-');
    return DateTime.tryParse('${d}T${s.substring(11, 19)}');
  }
}

/// **共享代码碰得到的唯一一处平台差异。**
///
/// 读元数据、出缩略图、出网页派生图、算精选信号、旋转 —— 这五件事每个平台的
/// 实现都不一样（macOS 用 ImageIO，手机用系统相册的解码器），但**调用方
/// 完全不关心**。共享层只依赖这个接口，App 启动时把自己那份实现塞进
/// [ImageOps.instance] 就行。
///
/// 默认实现是 [NoImageOps]：全部安全降级，不抛异常。这样一个还没接上原生层的
/// 平台（比如 Windows）也能把 App 跑起来，只是没有缩略图。
abstract class ImageOps {
  static ImageOps _instance = const NoImageOps();

  static ImageOps get instance => _instance;

  /// App 启动时调一次，在跑任何界面代码之前。
  static void register(ImageOps ops) => _instance = ops;

  /// 这个平台是否真的接上了原生实现。
  bool get supported;

  Future<PhotoMeta> readMetadata(String path);

  /// [background] 为真时走低优先级队列，系统会在前台忙时自动让路。
  Future<bool> makeThumbnail(
    String path,
    String destPath, {
    int maxPixels = 480,
    bool background = false,
  });

  /// 导出网页用的派生图：缩放 + 烤进方向 + **剥掉全部元数据**。
  /// 优先 WebP，系统不支持时退回 JPEG（返回值里说明实际格式与路径）。
  Future<ExportedImage?> exportWeb(
    String path,
    String destPath, {
    int maxPixels = 1600,
    double quality = 0.82,
    bool forceJpeg = false,
  });

  /// 分析一张图，算出自动精选需要的信号。
  /// 传入的应该是**已生成的缩略图**，不是原图 —— 省一次全尺寸解码。
  Future<PhotoSignals?> analyze(String path);

  /// 旋转照片 90 度并写回原文件。
  /// 不重新编码像素，只改 EXIF 方向标记 —— 画质零损失，拍摄时间不变。
  /// 返回 null 表示成功，否则是错误说明。
  Future<String?> rotate(String path, {bool clockwise = true});
}

/// 没有原生实现时的兜底。
class NoImageOps implements ImageOps {
  const NoImageOps();

  @override
  bool get supported => false;

  @override
  Future<PhotoMeta> readMetadata(String path) async => const PhotoMeta();

  @override
  Future<bool> makeThumbnail(String path, String destPath,
          {int maxPixels = 480, bool background = false}) async =>
      false;

  @override
  Future<ExportedImage?> exportWeb(String path, String destPath,
          {int maxPixels = 1600,
          double quality = 0.82,
          bool forceJpeg = false}) async =>
      null;

  @override
  Future<PhotoSignals?> analyze(String path) async => null;

  @override
  Future<String?> rotate(String path, {bool clockwise = true}) async =>
      tr('当前平台还不支持旋转');
}
