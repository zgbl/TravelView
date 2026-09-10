import 'package:flutter/material.dart';
import 'package:tv_core/tv_core.dart';

import '../state/library_controller.dart';
import 'package:tv_shared/tv_shared.dart';
import '../pages/photo_viewer.dart';
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

  /// 全部照片按界面显示顺序摊平 —— 查看器里左右翻页就能跨日期连续浏览
  List<PhotoRecord> _flatPhotos() {
    final out = <PhotoRecord>[];
    for (final day in c.byDay) {
      out.addAll(day.value);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final days = c.byDay;
    if (days.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, box) {
        final usable = box.maxWidth - 48 - 2; // 留 2px 余量，防止取整误差撑爆行
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
            Text(trf('{0} 张', [row.count]),
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
          // 注意: 最后一个 tile 后面不能再加间隔，否则整行宽度超出可用空间
          for (var i = 0; i < row.items.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            PhotoTile(
              record: row.items[i],
              file: c.fileOf(row.items[i]),
              thumbs: c.thumbs!,
              size: tileSize,
              picked: c.isPicked(
                  c.catalog?.byId(row.items[i].id) ?? row.items[i]),
              onTap: () {
                final all = _flatPhotos();
                final at = all.indexWhere((e) => e.id == row.items[i].id);
                if (at >= 0) {
                  PhotoViewer.open(context, c: c, photos: all, index: at);
                }
              },
            ),
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
