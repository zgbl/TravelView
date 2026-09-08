import 'package:flutter/material.dart';

import '../state/library_controller.dart';
import '../state/l10n.dart';

class StatBar extends StatelessWidget {
  final LibraryController c;
  const StatBar({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final gpsRatio = c.photoCount == 0 ? 0.0 : c.gpsCount / c.photoCount;
    return Row(
      children: [
        _Stat(label: tr('照片'), value: '${c.photoCount}'),
        _Stat(label: tr('占用'), value: humanBytes(c.totalBytes)),
        _Stat(
          label: tr('含 GPS'),
          value: '${c.gpsCount}',
          hint: '${(gpsRatio * 100).toStringAsFixed(0)}%',
        ),
        _Stat(
          label: trf('已选「{0}」', [c.pickAlbum]),
          value: '${c.pickedCount}',
        ),
        _Stat(
          label: tr('待处理'),
          value: '${c.issues.length}',
          warn: c.issues.isNotEmpty,
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final bool warn;

  const _Stat({
    required this.label,
    required this.value,
    this.hint,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: warn ? scheme.error : scheme.onSurface,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(width: 4),
                Text(
                  hint!,
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
