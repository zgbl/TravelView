import 'dart:async';
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

  /// 同时最多几个解码任务。放开会把平台通道塞满、拖慢滚动；
  /// 太小则首屏出图慢。4 是在 M1 上滚动流畅与出图速度之间的折中。
  static const _maxConcurrent = 4;
  int _running = 0;

  /// 两条等待队列。**前台永远优先**: 用户正在看的那几张要立刻出图，
  /// 后台预热排在它们后面，这样预热跑着也不会拖慢滚动。
  final _fg = <Completer<void>>[];
  final _bg = <Completer<void>>[];

  ThumbnailCache(this.libraryRoot);

  /// 派生图分两档: thumbs 给列表，previews 给全图查看。
  /// 都放在 catalog/ 下 —— 属于可随时删除重建的派生数据。
  File pathFor(String photoId, {String variant = 'thumbs'}) => File(p.join(
      libraryRoot.path, LibraryLayout.catalogDir, variant, '$photoId.jpg'));

  Future<File?> get(
    String photoId,
    File source, {
    int maxPixels = 480,
    bool background = false,
    String variant = 'thumbs',
  }) {
    return _memo.putIfAbsent('$variant/$photoId', () async {
      final dst = pathFor(photoId, variant: variant);
      if (await dst.exists()) return dst;
      await _acquire(background);
      try {
        final ok = await NativeBridge.makeThumbnail(
          source.path,
          dst.path,
          maxPixels: maxPixels,
          background: background,
        );
        return ok && await dst.exists() ? dst : null;
      } finally {
        _release();
      }
    });
  }

  /// 已经生成过就跳过，连平台通道都不用走
  Future<bool> exists(String photoId, {String variant = 'thumbs'}) =>
      pathFor(photoId, variant: variant).exists();

  /// 全图查看用的大图。2400px 在 5K 屏上够清晰，
  /// 又远小于原图，解码快得多。
  Future<File?> preview(String photoId, File source) =>
      get(photoId, source, maxPixels: 2400, variant: 'previews');

  Future<void> _acquire(bool background) {
    if (_running < _maxConcurrent) {
      _running++;
      return Future.value();
    }
    final c = Completer<void>();
    (background ? _bg : _fg).add(c);
    return c.future;
  }

  void _release() {
    if (_fg.isNotEmpty) {
      _fg.removeAt(0).complete();
    } else if (_bg.isNotEmpty) {
      _bg.removeAt(0).complete();
    } else {
      _running--;
    }
  }
}

/// 后台批量预生成缩略图。
///
/// 目标是"浏览时完全没有等待"，同时**绝不影响前台操作**:
///   - 走低优先级的原生队列，系统会在前台忙时自动让路
///   - 排在前台请求之后（见 ThumbnailCache 的两条队列）
///   - 每张之间让出一次事件循环，不阻塞 UI 帧
///   - 库变化或关闭时可随时取消
class ThumbnailWarmer {
  final ThumbnailCache cache;
  final void Function(int done, int total) onProgress;

  bool _cancelled = false;
  bool running = false;

  ThumbnailWarmer({required this.cache, required this.onProgress});

  void cancel() => _cancelled = true;

  /// [items] 应按用户最可能浏览的顺序排列，这样等待感最小。
  Future<void> run(List<MapEntry<String, File>> items) async {
    if (running) return;
    running = true;
    _cancelled = false;
    var done = 0;
    try {
      for (final e in items) {
        if (_cancelled) break;
        if (!await cache.exists(e.key)) {
          await cache.get(e.key, e.value, background: true);
        }
        done++;
        if (done % 20 == 0 || done == items.length) {
          onProgress(done, items.length);
        }
        // 让出事件循环，保证 UI 帧不被连续的解码请求挤掉
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      running = false;
      if (!_cancelled) onProgress(items.length, items.length);
    }
  }
}

const _directlyDecodable = {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'};
const _videoExt = {'.mov', '.mp4', '.m4v', '.avi'};

class PhotoTile extends StatelessWidget {
  final PhotoRecord record;
  final File file;
  final ThumbnailCache thumbs;
  final double size;
  final VoidCallback? onTap;
  final bool picked;

  const PhotoTile({
    super.key,
    required this.record,
    required this.file,
    required this.thumbs,
    this.size = 116,
    this.onTap,
    this.picked = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ext = p.extension(file.path).toLowerCase();
    final isVideo = _videoExt.contains(ext);

    return Tooltip(
      message: _tooltip(),
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: onTap == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          child: SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _image(scheme, ext),
              if (picked)
                IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: const Color(0xFF4FBFA8), width: 3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              if (picked)
                const Positioned(
                  right: 4,
                  top: 4,
                  child: Icon(Icons.check_circle,
                      size: 17, color: Color(0xFF4FBFA8)),
                ),
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
