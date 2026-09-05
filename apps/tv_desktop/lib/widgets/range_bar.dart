import 'package:flutter/material.dart';
import 'package:tv_core/tv_core.dart';

import '../state/library_controller.dart';

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
        Icon(Icons.filter_alt_outlined, size: 16, color: scheme.primary),
        const SizedBox(width: 8),
        _chip(
          context,
          label: '全部',
          selected: !c.hasRange,
          onTap: c.clearRange,
        ),
        for (final y in years)
          _chip(
            context,
            label: '$y',
            selected: _isYearSelected(y),
            onTap: () => c.setRange(DateTime(y), DateTime(y, 12, 31)),
          ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => _pick(context),
          icon: const Icon(Icons.date_range, size: 15),
          label: Text(_label(), style: const TextStyle(fontSize: 12)),
        ),
        if (c.hasRange)
          IconButton(
            tooltip: '清除筛选',
            onPressed: c.clearRange,
            icon: const Icon(Icons.close, size: 15),
          ),
        const SizedBox(width: 12),
        Text(
          c.hasRange
              ? '范围内 ${c.visibleCount} / ${c.photoCount} 张'
              : '共 ${c.photoCount} 张',
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
      c.rangeEnd == DateTime(y, 12, 31).add(const Duration(days: 1));

  String _label() {
    if (!c.hasRange) return '自定义时间范围';
    final from = c.rangeStart;
    final to = c.rangeEnd?.subtract(const Duration(days: 1));
    final a = from == null ? '最早' : LibraryLayout.dateStamp(from);
    final b = to == null ? '最新' : LibraryLayout.dateStamp(to);
    return '$a ~ $b';
  }

  Future<void> _pick(BuildContext context) async {
    final span = c.libraryTimeSpan;
    final first = span == null ? DateTime(2000) : span.$1;
    final last = span == null ? DateTime.now() : span.$2;
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(first.year - 1),
      lastDate: DateTime(last.year + 1, 12, 31),
      initialDateRange: c.rangeStart != null && c.rangeEnd != null
          ? DateTimeRange(
              start: c.rangeStart!,
              end: c.rangeEnd!.subtract(const Duration(days: 1)))
          : DateTimeRange(start: first, end: last),
      helpText: '选择要做行程报告的时间范围',
    );
    if (r != null) c.setRange(r.start, r.end);
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
