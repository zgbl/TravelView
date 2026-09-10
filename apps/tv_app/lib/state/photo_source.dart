import 'dart:async';
import 'dart:io';

import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:photo_manager/photo_manager.dart';
import 'package:tv_core/tv_core.dart';

/// 手机端的照片来源：**系统相册本身**。
///
/// 桌面端的库是"把照片按内容哈希收进一个目录"，手机端**故意不这么做** ——
/// 手机里已经有一份完整的相册了，再在 App 沙盒里存第二份，等于凭空吃掉
/// 几十 GB，还要处理两份之间的同步。所以这里只做一件事：
/// 把系统相册的元数据读成 [PhotoRecord]，让 `tv_core` 的精选、聚类、
/// 成篇算法**一行都不用改**就能跑在手机上。
///
/// 代价是 [PhotoRecord.id] 不是内容哈希，而是系统给的资产 id
/// （iOS 的 localIdentifier / Android 的 MediaStore id）。
/// 这个 id **只在这台手机上有意义**，所以：
///   - 不写进 sidecar，不参与库的自愈
///   - 发布时上传的是导出的派生图，服务器那边用派生图自己的哈希做身份
/// 也就是说手机端是照片库的**读者**，不是它的第二个副本。
class PhotoSource {
  PhotoSource._();
  static final PhotoSource instance = PhotoSource._();

  /// 资产 id -> 系统资产。缩略图、原图、导出都要回头找它。
  final Map<String, AssetEntity> _assets = {};

  AssetEntity? asset(String id) => _assets[id];

  /// 系统相册权限。
  ///
  /// iOS 允许用户只授权"选中的照片"，Android 14 也有类似的部分授权。
  /// 这种情况下 [PermissionState.limited] 是**成功**，不是失败 ——
  /// 直接当作被拒会让一大批用户卡在第一屏。
  Future<PermissionState> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend();
    if (state.hasAccess) await _requestMediaLocation();
    return state;
  }

  /// 照片里的 GPS 在 Android 10+ 是**一个独立的运行时权限**。
  ///
  /// 这是最容易踩的坑：相册权限给了、照片也读到了，但每一张的经纬度都是空的，
  /// 看起来像"用户的照片没开定位"，其实是系统在返回给 App 之前把位置抹掉了。
  /// `photo_manager` 的权限请求**不包含这一条**，必须自己要。
  ///
  /// 系统不会为它弹框（它是 auto-granted 类的权限，只要 manifest 里声明了、
  /// 并且相册权限已经给了就会通过），所以失败了也不用提示用户 ——
  /// 顶多是没有位置，界面上那句"照片里读不到位置"会告诉他去哪里检查。
  Future<bool> _requestMediaLocation() async {
    if (!Platform.isAndroid) return true;
    try {
      final st = await ph.Permission.accessMediaLocation.request();
      return st.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// 读整个相册的元数据。
  ///
  /// 只读元数据，不解码任何一张图 —— 一万张照片也就几秒。
  /// [onProgress] 给界面报进度（已读 / 总数）。
  Future<List<PhotoRecord>> scan({
    void Function(int done, int total)? onProgress,
  }) async {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(needTitle: true),
        orders: [const OrderOption(type: OrderOptionType.createDate)],
      ),
    );
    if (albums.isEmpty) return const [];

    final all = albums.first;
    final total = await all.assetCountAsync;
    final out = <PhotoRecord>[];

    // 分页取，一次全要会在老机器上直接爆内存
    const page = 500;
    for (var start = 0; start < total; start += page) {
      final batch = await all.getAssetListRange(
        start: start,
        end: (start + page).clamp(0, total),
      );
      for (final a in batch) {
        _assets[a.id] = a;
        out.add(await _toRecord(a));
      }
      onProgress?.call(out.length, total);
    }
    return out;
  }

  /// 各家系统给截图起的名字。中文机型上是"截屏"。
  static final _screenshotName =
      RegExp(r'screen ?shot|截屏|截图', caseSensitive: false);

  Future<PhotoRecord> _toRecord(AssetEntity a) async {
    // latitude/longitude 在 iOS 上可能是 0 而不是 null —— 0,0 是几内亚湾里的
    // 一个点，几乎不可能是真实拍摄地，当作"没有位置"处理。
    double? lat = a.latitude;
    double? lon = a.longitude;
    if (lat == null || lon == null || (lat == 0 && lon == 0)) {
      // 3.x 的 latlngAsync() 返回可空：这张图根本没有位置信息时给 null
      final ll = await a.latlngAsync();
      lat = ll?.latitude;
      lon = ll?.longitude;
    }
    final hasGps = lat != null && lon != null && !(lat == 0 && lon == 0);

    final title = a.title ?? a.id;
    return PhotoRecord(
      id: a.id,
      takenAt: a.createDateTime,
      // 相册不给文件大小，而且为了拿它去 stat 每一个文件会让扫描慢十倍。
      // 这个字段只在"库占了多少空间"的统计里用得到，手机端根本不显示。
      bytes: 0,
      origFilename: title,
      lat: hasGps ? lat : null,
      lon: hasGps ? lon : null,
      width: a.width,
      height: a.height,
      mime: a.mimeType,
      // 截图不该进旅行回顾。iOS 的 PHAssetMediaSubtype 里截图是第 4 位，
      // Android 没有对应的标记，只能看文件名 —— 两边都不准，所以还叠了
      // "没有 GPS"这个条件：真正在路上拍的照片几乎都带位置。
      isScreenshot: (a.subtype & 8) != 0 ||
          (!hasGps && _screenshotName.hasMatch(title)),
    );
  }
}
