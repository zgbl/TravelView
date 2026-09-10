import 'dart:io';

import 'package:flutter/services.dart';

import 'package:tv_shared/tv_shared.dart';

class PhoneDevice {
  final String id;
  final String name;
  final int itemCount;
  final bool open;

  const PhoneDevice({
    required this.id,
    required this.name,
    required this.itemCount,
    required this.open,
  });

  factory PhoneDevice.fromMap(Map m) => PhoneDevice(
        id: m['id'] as String,
        name: m['name'] as String? ?? tr('未知设备'),
        itemCount: (m['itemCount'] as num?)?.toInt() ?? 0,
        open: m['open'] as bool? ?? false,
      );
}

/// 手机上的一个文件。
///
/// `key` 才是身份，不是 `name` —— iPhone 的 DCIM 分成 100APPLE / 101APPLE 等
/// 多个文件夹，计数器到 IMG_9999 会绕回，不同年份的照片会重名。
class PhoneItem {
  final String key;
  final String name;
  final int size;
  final DateTime? created;
  final String? uti;

  const PhoneItem({
    required this.key,
    required this.name,
    required this.size,
    this.created,
    this.uti,
  });

  factory PhoneItem.fromMap(Map m) => PhoneItem(
        key: m['key'] as String? ?? m['name'] as String? ?? '',
        name: m['name'] as String? ?? '',
        size: (m['size'] as num?)?.toInt() ?? 0,
        created: m['created'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((m['created'] as num).toInt()),
        uti: m['uti'] as String?,
      );
}

class DownloadedFile {
  final String path;
  final String origName;
  const DownloadedFile({required this.path, required this.origName});
}

/// 与原生层的唯一通道。Windows 暂未实现，调用会安全降级。
class NativeBridge {
  static const _channel = MethodChannel('travelview/phone');

  static bool get supported => Platform.isMacOS;

  static void setDownloadProgressHandler(
    void Function(int done, int total, String name, String? error)? handler,
  ) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDownloadProgress' && handler != null) {
        final a = call.arguments as Map;
        handler(
          (a['done'] as num).toInt(),
          (a['total'] as num).toInt(),
          a['name'] as String? ?? '',
          a['error'] as String?,
        );
      }
      return null;
    });
  }

  static Future<List<PhoneDevice>> listDevices() async {
    if (!supported) return const [];
    final r = await _channel.invokeMethod<List<Object?>>('listDevices');
    return (r ?? [])
        .whereType<Map>()
        .map(PhoneDevice.fromMap)
        .toList();
  }

  static Future<int> openDevice(String deviceId) async {
    final r = await _channel
        .invokeMethod<Map>('openDevice', {'deviceId': deviceId});
    return (r?['itemCount'] as num?)?.toInt() ?? 0;
  }

  static Future<List<PhoneItem>> listItems(String deviceId) async {
    final r = await _channel
        .invokeMethod<List<Object?>>('listItems', {'deviceId': deviceId});
    return (r ?? []).whereType<Map>().map(PhoneItem.fromMap).toList();
  }

  /// 把选中的文件下载到一个临时目录。**只读手机，不删不改。**
  ///
  /// `keys` 传的是 [PhoneItem.key]（文件夹路径+文件名），不是裸文件名。
  /// 返回每个文件的中转路径和它在手机上的原始文件名。
  static Future<List<DownloadedFile>> downloadItems({
    required String deviceId,
    required List<String> keys,
    required String destDir,
  }) async {
    final r = await _channel.invokeMethod<List<Object?>>('downloadItems', {
      'deviceId': deviceId,
      'names': keys,
      'destDir': destDir,
    });
    return (r ?? [])
        .whereType<Map>()
        .map((m) => DownloadedFile(
              path: m['path'] as String? ?? '',
              origName: m['name'] as String? ?? '',
            ))
        .where((e) => e.path.isNotEmpty)
        .toList();
  }

  static Future<void> closeDevice(String deviceId) async {
    if (!supported) return;
    await _channel.invokeMethod('closeDevice', {'deviceId': deviceId});
  }

  static Future<PhotoMeta> readMetadata(String path) async {
    if (!supported) return const PhotoMeta();
    try {
      final m = await _channel
          .invokeMethod<Map>('readMetadata', {'path': path});
      if (m == null) return const PhotoMeta();
      return PhotoMeta(
        takenAt: PhotoMeta.parseExifDate(m['takenAt'] as String?),
        lat: (m['lat'] as num?)?.toDouble(),
        lon: (m['lon'] as num?)?.toDouble(),
        width: (m['width'] as num?)?.toInt(),
        height: (m['height'] as num?)?.toInt(),
        device: m['device'] as String?,
      );
    } catch (_) {
      return const PhotoMeta();
    }
  }

  /// [background] 为真时走低优先级队列，系统会在前台忙时自动让路。
  static Future<bool> makeThumbnail(
    String path,
    String destPath, {
    int maxPixels = 480,
    bool background = false,
  }) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('makeThumbnail', {
            'path': path,
            'destPath': destPath,
            'maxPixels': maxPixels,
            'background': background,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 导出网页用的派生图: 缩放 + 烤进方向 + **剥掉全部元数据**。
  /// 优先 WebP，系统不支持时退回 JPEG（返回值里说明实际格式与路径）。
  static Future<ExportedImage?> exportWeb(
    String path,
    String destPath, {
    int maxPixels = 1600,
    double quality = 0.82,
    bool forceJpeg = false,
  }) async {
    if (!supported) return null;
    try {
      final m = await _channel.invokeMethod<Map>('exportWeb', {
        'path': path,
        'destPath': destPath,
        'maxPixels': maxPixels,
        'quality': quality,
        'forceJpeg': forceJpeg,
      });
      if (m == null || m['ok'] != true) return null;
      return ExportedImage(
        path: m['path'] as String,
        format: m['format'] as String? ?? 'jpeg',
        width: (m['width'] as num?)?.toInt() ?? 0,
        height: (m['height'] as num?)?.toInt() ?? 0,
        bytes: (m['bytes'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// 分析一张图，算出自动精选需要的信号（清晰度、亮度、感知哈希、人脸数）。
  /// 传入的应该是**已生成的缩略图**，不是原图 —— 省一次全尺寸解码。
  static Future<PhotoSignals?> analyze(String path) async {
    if (!supported) return null;
    try {
      final m = await _channel.invokeMethod<Map>('analyze', {'path': path});
      if (m == null || m['phash'] == null) return null;
      return PhotoSignals(
        sharpness: (m['sharpness'] as num?)?.toDouble(),
        brightness: (m['brightness'] as num?)?.toDouble(),
        phash: m['phash'] as String?,
        faceCount: (m['faceCount'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 旋转照片 90 度并写回原文件。
  /// 不重新编码像素，只改 EXIF 方向标记 —— 画质零损失，拍摄时间不变。
  /// 返回 null 表示成功，否则是错误说明。
  static Future<String?> rotate(String path, {bool clockwise = true}) async {
    if (!supported) return tr('当前平台还不支持旋转');
    try {
      final m = await _channel.invokeMethod<Map>('rotate', {
        'path': path,
        'clockwise': clockwise,
      });
      if (m == null) return tr('旋转失败');
      if (m['ok'] == true) return null;
      return m['error'] as String? ?? tr('旋转失败');
    } catch (e) {
      return '$e';
    }
  }

}

/// 把 [NativeBridge] 的静态方法包成共享层认识的 [ImageOps]。
///
/// 桌面端在 `main()` 里 `ImageOps.register(const DesktopImageOps())`，
/// 之后 `tv_shared` 里的 Story 导出就能用上 macOS 的 ImageIO，
/// 而共享代码里一个 `MethodChannel` 都不会出现。
class DesktopImageOps implements ImageOps {
  const DesktopImageOps();

  @override
  bool get supported => NativeBridge.supported;

  @override
  Future<PhotoMeta> readMetadata(String path) =>
      NativeBridge.readMetadata(path);

  @override
  Future<bool> makeThumbnail(String path, String destPath,
          {int maxPixels = 480, bool background = false}) =>
      NativeBridge.makeThumbnail(path, destPath,
          maxPixels: maxPixels, background: background);

  @override
  Future<ExportedImage?> exportWeb(String path, String destPath,
          {int maxPixels = 1600,
          double quality = 0.82,
          bool forceJpeg = false}) =>
      NativeBridge.exportWeb(path, destPath,
          maxPixels: maxPixels, quality: quality, forceJpeg: forceJpeg);

  @override
  Future<PhotoSignals?> analyze(String path) => NativeBridge.analyze(path);

  @override
  Future<String?> rotate(String path, {bool clockwise = true}) =>
      NativeBridge.rotate(path, clockwise: clockwise);
}
