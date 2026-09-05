import 'package:flutter/material.dart';
import 'package:tv_core/tv_core.dart';

/// 时间范围选择。**日期和时分都能直接改** ——
/// 做单日内的分段行程报告时，只能选到"天"是不够的。
class RangeDialog extends StatefulWidget {
  final DateTime? start;
  final DateTime? end;
  final DateTime firstDate;
  final DateTime lastDate;

  const RangeDialog({
    super.key,
    this.start,
    this.end,
    required this.firstDate,
    required this.lastDate,
  });

  static Future<(DateTime?, DateTime?)?> show(
    BuildContext context, {
    DateTime? start,
    DateTime? end,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    return showDialog<(DateTime?, DateTime?)>(
      context: context,
      builder: (_) => RangeDialog(
        start: start,
        end: end,
        firstDate: firstDate,
        lastDate: lastDate,
      ),
    );
  }

  @override
  State<RangeDialog> createState() => _RangeDialogState();
}

class _RangeDialogState extends State<RangeDialog> {
  late DateTime start = widget.start ??
      DateTime(widget.firstDate.year, widget.firstDate.month,
          widget.firstDate.day);
  late DateTime end = widget.end ??
      DateTime(widget.lastDate.year, widget.lastDate.month,
          widget.lastDate.day, 23, 59, 59);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('选择时间范围'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '做行程报告时用这个范围。日期和时分都可以改 —— '
              '同一天里想切成上午、下午两段时会用到。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            _row('开始', start, (v) => setState(() => start = v), isStart: true),
            const SizedBox(height: 12),
            _row('结束', end, (v) => setState(() => end = v), isStart: false),
            const SizedBox(height: 18),
            if (!end.isAfter(start))
              Text('结束时间必须晚于开始时间',
                  style: TextStyle(fontSize: 12, color: scheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop((null, null)),
          child: const Text('不筛选（看全部）'),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: end.isAfter(start)
              ? () => Navigator.of(context).pop((start, end))
              : null,
          child: const Text('应用'),
        ),
      ],
    );
  }

  Widget _row(String label, DateTime value, ValueChanged<DateTime> onChange,
      {required bool isStart}) {
    return Row(
      children: [
        SizedBox(
            width: 40,
            child: Text(label, style: const TextStyle(fontSize: 13))),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime(widget.firstDate.year - 1),
              lastDate: DateTime(widget.lastDate.year + 1, 12, 31),
            );
            if (d != null) {
              onChange(DateTime(
                  d.year, d.month, d.day, value.hour, value.minute,
                  isStart ? 0 : 59));
            }
          },
          icon: const Icon(Icons.calendar_today, size: 14),
          label: Text(LibraryLayout.dateStamp(value)),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: () async {
            final t = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: value.hour, minute: value.minute),
            );
            if (t != null) {
              onChange(DateTime(value.year, value.month, value.day, t.hour,
                  t.minute, isStart ? 0 : 59));
            }
          },
          icon: const Icon(Icons.schedule, size: 14),
          label: Text(
            '${value.hour.toString().padLeft(2, '0')}:'
            '${value.minute.toString().padLeft(2, '0')}',
          ),
        ),
      ],
    );
  }
}
