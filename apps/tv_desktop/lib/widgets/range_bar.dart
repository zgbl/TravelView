import 'package:flutter/material.dart';
import 'package:tv_core/tv_core.dart';

import '../state/library_controller.dart';
import '../state/l10n.dart';
import 'range_dialog.dart';

/// 全局时间范围条。照片视图和行程地图共用同一个范围。
///
/// 设计要点: **照片库只有一个，装全部照片**。想做哪段行程的报告，
/// 就把范围调到哪段 —— 不需要为此把照片再导一份到别的文件夹。
class RangeBar extends StatelessWidget {
  final LibraryController c;
  const RangeBar({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final years = _years();

    return Row(
      children: [
        // 窗口变窄时这一排会放不下，让它自己横向滚动，而不是溢出报错
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
        Icon(Icons.filter_alt_outlined, size: 16, color: scheme.primary),
        const SizedBox(width: 8),
        _chip(
          context,
          label: tr('全部'),
          selected: !c.hasRange,
          onTap: c.clearRange,
        ),
        for (final y in years)
          _chip(
            context,
            label: '$y',
            selected: _isYearSelected(y),
            onTap: () => c.setDayRange(DateTime(y), DateTime(y, 12, 31)),
          ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => _pick(context),
          icon: const Icon(Icons.date_range, size: 15),
          label: Text(_label(), style: const TextStyle(fontSize: 12)),
        ),
        if (c.hasRange)
          IconButton(
            tooltip: tr('清除筛选'),
            onPressed: c.clearRange,
            icon: const Icon(Icons.close, size: 15),
          ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          c.hasRange
              ? trf('范围内 {0} / {1} 张', [c.visibleCount, c.photoCount])
              : trf('共 {0} 张', [c.photoCount]),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  List<int> _years() {
    final span = c.libraryTimeSpan;
    if (span == null) return const [];
    final out = <int>[];
    for (var y = span.$2.year; y >= span.$1.year && out.length < 6; y--) {
      out.add(y);
    }
    return out;
  }

  bool _isYearSelected(int y) =>
      c.rangeStart == DateTime(y) &&
      c.rangeEnd == DateTime(y, 12, 31, 23, 59, 59);

  String _label() {
    if (!c.hasRange) return tr('自定义时间范围');
    return '${_stamp(c.rangeStart, tr('最早'))} ~ ${_stamp(c.rangeEnd, tr('最新'))}';
  }

  /// 精确到分钟 —— 同一天可能要切成上下午两段行程
  static String _stamp(DateTime? t, String fallback) {
    if (t == null) return fallback;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${LibraryLayout.dateStamp(t)} $hh:$mm';
  }

  Future<void> _pick(BuildContext context) async {
    final span = c.libraryTimeSpan;
    final r = await RangeDialog.show(
      context,
      start: c.rangeStart,
      end: c.rangeEnd,
      firstDate: span?.$1 ?? DateTime(2000),
      lastDate: span?.$2 ?? DateTime.now(),
    );
    if (r != null) c.setRange(r.$1, r.$2);
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
