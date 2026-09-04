import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tv_core/tv_core.dart';

/// Flutter 自带的解码器不认 HEIC，所以 iPhone 的照片暂时显示成带类型标签的占位块。
/// （后续用平台通道调系统解码器补上，见 Design/architecture.md）
const _decodable = {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'};

class PhotoTile extends StatelessWidget {
  final PhotoRecord record;
  final File file;
  final double size;

  const PhotoTile({
    super.key,
    required this.record,
    required this.file,
    this.size = 116,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ext = p.extension(file.path).toLowerCase();
    final canDecode = _decodable.contains(ext);

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
              if (canDecode)
                Image.file(
                  file,
                  fit: BoxFit.cover,
                  cacheWidth: (size * 2).round(),
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => _placeholder(scheme, ext),
                )
              else
                _placeholder(scheme, ext),
              if (record.hasLocation)
                Positioned(
                  right: 5,
                  bottom: 5,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.place_outlined,
                        size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

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
    return b.toString();
  }

  Widget _placeholder(ColorScheme scheme, String ext) {
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined,
              size: 22, color: scheme.onSurfaceVariant),
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
