import 'package:flutter/material.dart';
import 'package:tv_core/tv_core.dart';

import '../native/native_bridge.dart';
import 'package:tv_shared/tv_shared.dart';
import '../state/library_controller.dart';

/// 从 iPhone 导入。手机上的照片全程只读。
class PhoneImportDialog extends StatefulWidget {
  final LibraryController controller;
  const PhoneImportDialog({super.key, required this.controller});

  @override
  State<PhoneImportDialog> createState() => _PhoneImportDialogState();
}

class _PhoneImportDialogState extends State<PhoneImportDialog> {
  List<PhoneDevice> devices = const [];
  PhoneDevice? selected;
  List<PhoneItem> items = const [];
  final Set<String> chosen = {};
  bool loading = false;
  String? error;
  DateTimeRange? range;
  final tripController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshDevices();
  }

  @override
  void dispose() {
    tripController.dispose();
    super.dispose();
  }

  Future<void> _refreshDevices() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await NativeBridge.listDevices();
      setState(() => devices = d);
    } catch (e) {
      setState(() => error = '$e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _open(PhoneDevice d) async {
    setState(() {
      loading = true;
      error = null;
      selected = d;
      items = const [];
      chosen.clear();
    });
    try {
      await NativeBridge.openDevice(d.id);
      final list = await NativeBridge.listItems(d.id);
      list.sort((a, b) => (a.created ?? DateTime(1970))
          .compareTo(b.created ?? DateTime(1970)));
      setState(() {
        items = list;
        chosen.addAll(list.map((e) => e.key));
      });
    } catch (e) {
      setState(() => error = '$e');
    } finally {
      setState(() => loading = false);
    }
  }

  List<PhoneItem> get filtered {
    if (range == null) return items;
    final start = DateTime(range!.start.year, range!.start.month, range!.start.day);
    final end = DateTime(range!.end.year, range!.end.month, range!.end.day)
        .add(const Duration(days: 1));
    return items
        .where((e) =>
            e.created != null &&
            e.created!.isAfter(start) &&
            e.created!.isBefore(end))
        .toList();
  }

  int get chosenBytes => filtered
      .where((e) => chosen.contains(e.key))
      .fold<int>(0, (a, e) => a + e.size);

  /// 拿不到拍摄时间的文件。设了日期范围时它们会被排除，
  /// 必须让用户知道漏了多少，不能默默丢掉。
  int get undatedCount => items.where((e) => e.created == null).length;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDateRange: range,
    );
    if (r != null) {
      setState(() {
        range = r;
        chosen
          ..clear()
          ..addAll(filtered.map((e) => e.key));
      });
    }
  }

  Future<void> _import() async {
    final keys =
        filtered.where((e) => chosen.contains(e.key)).map((e) => e.key).toList();
    if (keys.isEmpty || selected == null) return;
    final trip = tripController.text.trim();
    Navigator.of(context).pop();
    await widget.controller.importFromPhone(
      deviceId: selected!.id,
      keys: keys,
      // 兜底: 即使设备侧筛选出了范围外的文件，入库时按 EXIF 拍摄时间再挡一道
      limitFrom: range?.start,
      limitUntil: range?.end,
      tags: trip.isEmpty ? const [] : [Tag('trip', trip)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      child: SizedBox(
        width: 720,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
              child: Row(
                children: [
                  Icon(Icons.phone_iphone, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text(tr('从手机导入'),
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    tooltip: tr('重新检测设备'),
                    onPressed: loading ? null : _refreshDevices,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                tr('手机上的照片全程只读 —— 只会复制到你的照片库，绝不修改或删除手机上的任何内容。'),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 14),
            if (loading) const LinearProgressIndicator(),
            Expanded(child: _body(context)),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Row(
                children: [
                  if (items.isNotEmpty) ...[
                    Text(_selectionSummary()),
                    const SizedBox(width: 16),
                    TextButton(
                      onPressed: () => setState(() => chosen
                        ..clear()
                        ..addAll(filtered.map((e) => e.key))),
                      child: Text(tr('全选')),
                    ),
                    TextButton(
                      onPressed: () => setState(chosen.clear),
                      child: Text(tr('清空')),
                    ),
                  ],
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(tr('取消')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: chosen.isEmpty || loading ? null : _import,
                    child: Text(tr('导入到照片库')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!NativeBridge.supported) {
      return _hint(tr('目前只有 macOS 支持直连手机读取，Windows 版还在做。\n'
          '在 Windows 上可以先用「导入照片」从文件夹导入。'));
    }
    if (error != null) {
      return _hint(error!, isError: true);
    }
    if (devices.isEmpty) {
      return _hint(tr('没有检测到设备。\n\n'
          '1. 用数据线把 iPhone 连到这台 Mac\n'
          '2. 在 iPhone 上点「信任此电脑」\n'
          '3. 保持手机解锁状态\n'
          '4. 点右上角的刷新'));
    }
    if (selected == null || items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: devices
            .map((d) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.phone_iphone),
                    title: Text(d.name),
                    subtitle: Text(d.itemCount > 0
                        ? trf('{0} 个项目', [d.itemCount])
                        : tr('点击读取')),
                    onTap: loading ? null : () => _open(d),
                  ),
                ))
            .toList(),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 10),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range, size: 16),
                label: Text(_rangeLabel()),
              ),
              if (range != null)
                IconButton(
                  tooltip: tr('清除筛选'),
                  onPressed: () => setState(() => range = null),
                  icon: const Icon(Icons.close, size: 16),
                ),
              const SizedBox(width: 16),
              if (range != null && undatedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Tooltip(
                    message: trf('{0} 个文件没有拍摄时间，日期筛选会把它们排除在外',
                        [undatedCount]),
                    child: Icon(Icons.info_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              Expanded(
                child: TextField(
                  controller: tripController,
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    labelText: tr('这批照片属于哪次旅行（可留空）'),
                    hintText: tr('例如 京都 2025'),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, i) {
              final it = filtered[i];
              final on = chosen.contains(it.key);
              return CheckboxListTile(
                dense: true,
                value: on,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    chosen.add(it.key);
                  } else {
                    chosen.remove(it.key);
                  }
                }),
                title: Text(it.name, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  _itemSubtitle(it),
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _rangeLabel() {
    if (range == null) return tr('按日期筛选');
    return '${LibraryLayout.dateStamp(range!.start)} ~ '
        '${LibraryLayout.dateStamp(range!.end)}';
  }

  String _itemSubtitle(PhoneItem it) {
    final when = it.created == null
        ? tr('时间未知')
        : '${LibraryLayout.dateStamp(it.created!)} ${LibraryLayout.timeStamp(it.created!)}';
    return '$when   ${humanBytes(it.size)}';
  }

  String _selectionSummary() {
    final n = chosen.where((k) => filtered.any((e) => e.key == k)).length;
    return trf('已选 {0} / {1} 张 · {2}',
        [n, filtered.length, humanBytes(chosenBytes)]);
  }

  Widget _hint(String text, {bool isError = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            height: 1.7,
            color: isError ? scheme.error : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
