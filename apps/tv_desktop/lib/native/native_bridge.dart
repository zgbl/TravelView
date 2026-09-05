import 'dart:io';

import 'package:flutter/services.dart';

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
        name: m['name'] as String? ?? '未知设备',
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

/// 照片的 EXIF 元数据。macOS 走 ImageIO，原生支持 HEIC。
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
        takenAt: _parseExifDate(m['takenAt'] as String?),
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

  static Future<bool> makeThumbnail(
      String path, String destPath, {int maxPixels = 480}) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('makeThumbnail', {
            'path': path,
            'destPath': destPath,
            'maxPixels': maxPixels,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// EXIF 的时间格式是 "2025:09:12 14:30:22"，不是 ISO8601。
  static DateTime? _parseExifDate(String? s) {
    if (s == null || s.length < 19) return null;
    final d = s.substring(0, 10).replaceAll(':', '-');
    return DateTime.tryParse('${d}T${s.substring(11, 19)}');
  }
}
