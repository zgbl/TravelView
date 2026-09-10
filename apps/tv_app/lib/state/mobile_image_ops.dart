import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:photo_manager/photo_manager.dart';
import 'package:tv_shared/tv_shared.dart';

import 'photo_source.dart';
import 'workspace.dart';

/// 手机端的 [ImageOps]。
///
/// 和桌面端有两处不同。
///
/// **一、传进来的 `path` 是资产 id，不是文件路径。**
/// 手机上照片在系统相册里，App 拿不到稳定的文件路径（iOS 的原件可能还在
/// iCloud 上没下载下来），只能通过资产 id 问系统要。共享层不需要知道这件事，
/// 它只管把 `PhotoRecord.id` 传下来。
///
/// **二、写出去的东西必须落在 [Workspace] 里。**
/// `destPath` 由调用方给，但调用方在手机上永远是从 `Workspace` 拿的路径。
/// 这里再兜一道底：不在工作目录里的写入直接拒绝，免得哪天某段共享代码
/// 按桌面端的习惯把文件写到用户的相册旁边去。
class MobileImageOps implements ImageOps {
  const MobileImageOps();

  @override
  bool get supported => true;

  /// 元数据在扫描相册时就已经从系统拿到了（见 [PhotoSource]），
  /// 这里不再解码一次文件。
  @override
  Future<PhotoMeta> readMetadata(String assetId) async {
    final a = PhotoSource.instance.asset(assetId);
    if (a == null) return const PhotoMeta();
    final ll = await a.latlngAsync();
    // 没有位置时 ll 本身是 null；有位置但值是 0,0 的，那是几内亚湾里的一个点，
    // 几乎不可能是真实拍摄地，同样当作没有
    final lat = ll?.latitude;
    final lon = ll?.longitude;
    final hasGps = lat != null && lon != null && !(lat == 0 && lon == 0);
    return PhotoMeta(
      takenAt: a.createDateTime,
      lat: hasGps ? lat : null,
      lon: hasGps ? lon : null,
      width: a.width,
      height: a.height,
    );
  }

  @override
  Future<bool> makeThumbnail(String assetId, String destPath,
      {int maxPixels = 480, bool background = false}) async {
    final a = PhotoSource.instance.asset(assetId);
    if (a == null) return false;
    final bytes = await a.thumbnailDataWithSize(
      ThumbnailSize.square(maxPixels),
      quality: 80,
    );
    if (bytes == null) return false;
    if (!_inWorkspace(destPath)) return false;
    final f = File(destPath);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
    return true;
  }

  @override
  Future<ExportedImage?> exportWeb(String assetId, String destPath,
      {int maxPixels = 1600,
      double quality = 0.82,
      bool forceJpeg = false}) async {
    final a = PhotoSource.instance.asset(assetId);
    if (a == null) return null;

    // 按长边缩放，保持比例。系统给的是 JPEG，**元数据已经被剥掉了** ——
    // 这正是发布需要的：分享出去的图不该带着家里的 GPS。
    final w = a.width, h = a.height;
    final scale = w >= h ? maxPixels / w : maxPixels / h;
    final tw = (w * (scale > 1 ? 1 : scale)).round();
    final th = (h * (scale > 1 ? 1 : scale)).round();

    final bytes = await a.thumbnailDataWithSize(
      ThumbnailSize(tw, th),
      quality: (quality * 100).round(),
    );
    if (bytes == null) return null;

    final out = destPath.endsWith('.jpg') ? destPath : '$destPath.jpg';
    if (!_inWorkspace(out)) return null;
    final f = File(out);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
    return ExportedImage(
      path: out,
      format: 'jpeg',
      width: tw,
      height: th,
      bytes: bytes.length,
    );
  }

  /// 清晰度 / 人脸 / 感知哈希还没接。
  ///
  /// 返回 null 时 `Curator` 会退回到"只按时间和位置聚类"，精选质量差一些，
  /// 但**不会崩、也不会挑出空结果** —— 这是手机端第一版可以接受的取舍。
  @override
  Future<PhotoSignals?> analyze(String path) async => null;

  /// 手机上不改动系统相册里的原件。要旋转就在系统相册里转，
  /// **这不是保守，是边界**：App 没有理由去写用户的原始照片。
  @override
  Future<String?> rotate(String path, {bool clockwise = true}) async =>
      tr('请在系统相册里旋转这张照片');
}

/// 只允许往 [Workspace] 里写。
bool _inWorkspace(String path) {
  try {
    return p.isWithin(Workspace.instance.root.path, path);
  } catch (_) {
    // Workspace 没初始化就说明 main() 写错了，宁可什么都不写
    return false;
  }
}
