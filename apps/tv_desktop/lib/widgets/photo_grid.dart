import 'package:flutter/material.dart';
import 'package:tv_core/tv_core.dart';

import '../state/library_controller.dart';
import 'photo_tile.dart';

/// 按天分组的照片网格。
///
/// 关键: 必须把"日期标题 + 每一行缩略图"摊平成一个线性列表交给 ListView.builder，
/// **只构建可见的那几行**。之前是 ListView 里套 Wrap，一个有 200 张照片的日期
/// 会一次性构建 200 个 tile，5000 张的库直接卡死。
class PhotoGrid extends StatelessWidget {
  final LibraryController c;
  final double tileSize;
  final double gap;

  const PhotoGrid({
    super.key,
    required this.c,
    this.tileSize = 116,
    this.gap = 8,
  });

  @override
  Widget build(BuildContext context) {
    final days = c.byDay;
    if (days.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, box) {
        final usable = box.maxWidth - 48;
        final perRow = ((usable + gap) / (tileSize + gap)).floor().clamp(1, 20);
        final rows = _flatten(days, perRow);

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
          itemCount: rows.length,
          itemBuilder: (context, i) => _buildRow(context, rows[i]),
        );
      },
    );
  }

  List<_Row> _flatten(
      List<MapEntry<String, List<PhotoRecord>>> days, int perRow) {
    final rows = <_Row>[];
    for (final day in days) {
      rows.add(_Row.header(day.key, day.value.length));
      for (var i = 0; i < day.value.length; i += perRow) {
        rows.add(_Row.photos(
          day.value.sublist(
              i, i + perRow > day.value.length ? day.value.length : i + perRow),
        ));
      }
    }
    return rows;
  }

  Widget _buildRow(BuildContext context, _Row row) {
    final scheme = Theme.of(context).colorScheme;
    if (row.header != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 12),
        child: Row(
          children: [
            Text(row.header!,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            Text('${row.count} 张',
                style:
                    TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Row(
        children: [
          for (final r in row.items) ...[
            PhotoTile(
              record: r,
              file: c.fileOf(r),
              thumbs: c.thumbs!,
              size: tileSize,
            ),
            SizedBox(width: gap),
          ],
        ],
      ),
    );
  }
}

class _Row {
  final String? header;
  final int count;
  final List<PhotoRecord> items;

  const _Row.header(String this.header, this.count) : items = const [];
  const _Row.photos(this.items)
      : header = null,
        count = 0;
}
