import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tv_core/tv_core.dart';

import '../native/native_bridge.dart';

/// Flutter 自带解码器不认 HEIC，视频也不能直接当图片显示。
/// 所以统一走系统解码器（macOS: ImageIO / AVFoundation）生成一张 JPEG 缩略图，
/// 缓存在 <库>/catalog/thumbs/<id>.jpg —— 属于派生数据，随时可删可重建。
class ThumbnailCache {
  final Directory libraryRoot;
  final _memo = <String, Future<File?>>{};

  ThumbnailCache(this.libraryRoot);

  File pathFor(String photoId) => File(
      p.join(libraryRoot.path, LibraryLayout.catalogDir, 'thumbs', '$photoId.jpg'));

  Future<File?> get(String photoId, File source, {int maxPixels = 480}) {
    return _memo.putIfAbsent(photoId, () async {
      final dst = pathFor(photoId);
      if (await dst.exists()) return dst;
      final ok = await NativeBridge.makeThumbnail(
        source.path,
        dst.path,
        maxPixels: maxPixels,
      );
      return ok && await dst.exists() ? dst : null;
    });
  }
}

const _directlyDecodable = {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'};
const _videoExt = {'.mov', '.mp4', '.m4v', '.avi'};

class PhotoTile extends StatelessWidget {
  final PhotoRecord record;
  final File file;
  final ThumbnailCache thumbs;
  final double size;

  const PhotoTile({
    super.key,
    required this.record,
    required this.file,
    required this.thumbs,
    this.size = 116,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ext = p.extension(file.path).toLowerCase();
    final isVideo = _videoExt.contains(ext);

    return Tooltip(
      message: _tooltip(),
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _image(scheme, ext),
              if (isVideo)
                Positioned(
                  left: 5,
                  top: 5,
                  child: _badge(const Icon(Icons.play_arrow,
                      size: 12, color: Colors.white)),
                ),
              if (record.editOf != null)
                Positioned(
                  left: 5,
                  bottom: 5,
                  child: _badge(const Icon(Icons.tune,
                      size: 11, color: Colors.white)),
                ),
              if (record.hasLocation)
                Positioned(
                  right: 5,
                  bottom: 5,
                  child: _badge(const Icon(Icons.place_outlined,
                      size: 12, color: Colors.white)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _image(ColorScheme scheme, String ext) {
    if (_directlyDecodable.contains(ext)) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: (size * 2).round(),
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _placeholder(scheme, ext),
      );
    }
    return FutureBuilder<File?>(
      future: thumbs.get(record.id, file, maxPixels: (size * 2).round()),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(color: scheme.surfaceContainerHighest);
        }
        final f = snap.data;
        if (f == null) return _placeholder(scheme, ext);
        return Image.file(
          f,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => _placeholder(scheme, ext),
        );
      },
    );
  }

  Widget _badge(Widget child) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
        ),
        child: child,
      );

  String _tooltip() {
    final b = StringBuffer(record.origFilename)
      ..write('\n')
      ..write(LibraryLayout.dateStamp(record.takenAt))
      ..write(' ')
      ..write(LibraryLayout.timeStamp(record.takenAt));
    if (record.hasLocation) {
      b
        ..write('\n')
        ..write(record.lat!.toStringAsFixed(4))
        ..write(', ')
        ..write(record.lon!.toStringAsFixed(4));
    }
    if (record.editOf != null) {
      b.write('\n（编辑后的版本）');
    }
    return b.toString();
  }

  Widget _placeholder(ColorScheme scheme, String ext) {
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: 22, color: scheme.onSurfaceVariant),
          const SizedBox(height: 4),
          Text(
            ext.replaceFirst('.', '').toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
