import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:tv_core/tv_core.dart';

import '../state/library_controller.dart';
import 'map_page.dart';
import 'phone_import_page.dart';
import '../widgets/photo_grid.dart';
import '../widgets/stat_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final c = LibraryController();
  int view = 0; // 0 = 照片, 1 = 地图

  @override
  void initState() {
    super.initState();
    c.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    c.dispose();
    super.dispose();
  }

  Future<void> _pickLibrary() async {
    final dir = await getDirectoryPath(confirmButtonText: '用作照片库');
    if (dir != null) await c.openLibrary(dir);
  }

  Future<void> _pickImportSource() async {
    final dir = await getDirectoryPath(confirmButtonText: '导入这个文件夹');
    if (dir != null) await c.importFrom(dir);
  }

  Future<void> _importFromPhone() async {
    await showDialog<void>(
      context: context,
      builder: (_) => PhoneImportDialog(controller: c),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            c: c,
            onOpen: _pickLibrary,
            onImport: _pickImportSource,
            onPhoneImport: _importFromPhone,
            selectedView: view,
            onView: (v) => setState(() => view = v),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: !c.hasLibrary
                ? _emptyState(context)
                : (view == 1 ? MapPage(key: ValueKey(c.photoCount), c: c) : _libraryView(context)),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined,
                size: 56, color: scheme.primary),
            const SizedBox(height: 20),
            Text('选择一个文件夹作为你的照片库',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(
              '照片会以普通文件的形式，按拍摄日期存进这个文件夹。\n'
              '没有数据库黑盒，没有专有格式 —— 十年后不装任何软件也能打开。',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _pickLibrary,
              icon: const Icon(Icons.folder_open),
              label: const Text('选择照片库文件夹'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _libraryView(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = c.byDay;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.root?.path ?? '',
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              StatBar(c: c),
            ],
          ),
        ),
        if (c.busy) LinearProgressIndicator(value: c.progress),
        Expanded(
          child: days.isEmpty ? _noPhotos(context) : PhotoGrid(c: c),
        ),
        _StatusBar(c: c),
      ],
    );
  }

  Widget _noPhotos(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('这个库还是空的',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('从一个文件夹导入照片开始',
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: c.busy ? null : _importFromPhone,
                icon: const Icon(Icons.phone_iphone),
                label: const Text('从 iPhone 导入'),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: c.busy ? null : _pickImportSource,
                icon: const Icon(Icons.folder_outlined),
                label: const Text('从文件夹导入'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final LibraryController c;
  final VoidCallback onOpen;
  final VoidCallback onImport;
  final VoidCallback onPhoneImport;
  final int selectedView;
  final ValueChanged<int> onView;

  const _Sidebar({
    required this.c,
    required this.onOpen,
    required this.onImport,
    required this.onPhoneImport,
    required this.selectedView,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 208,
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(14, 24, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.travel_explore, color: scheme.primary, size: 22),
              const SizedBox(width: 8),
              Text('TravelView',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 28),
          _Action(
            icon: Icons.folder_open,
            label: '打开照片库',
            onTap: c.busy ? null : onOpen,
          ),
          _Action(
            icon: Icons.phone_iphone,
            label: '从手机导入',
            onTap: c.busy || !c.hasLibrary ? null : onPhoneImport,
          ),
          _Action(
            icon: Icons.folder_outlined,
            label: '从文件夹导入',
            onTap: c.busy || !c.hasLibrary ? null : onImport,
          ),
          const SizedBox(height: 14),
          _Action(
            icon: Icons.photo_library_outlined,
            label: '照片',
            selected: selectedView == 0,
            onTap: !c.hasLibrary ? null : () => onView(0),
          ),
          _Action(
            icon: Icons.map_outlined,
            label: '行程地图',
            selected: selectedView == 1,
            onTap: !c.hasLibrary ? null : () => onView(1),
          ),
          const SizedBox(height: 14),
          _Action(
            icon: Icons.refresh,
            label: '重建索引',
            onTap: c.busy || !c.hasLibrary ? null : c.rebuild,
          ),
          _Action(
            icon: Icons.verified_outlined,
            label: '校验完整性',
            onTap: c.busy || !c.hasLibrary ? null : c.verify,
          ),
          const Spacer(),
          if (c.issues.isNotEmpty) _IssueSummary(issues: c.issues),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  const _Action({
    required this.icon,
    required this.label,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            decoration: BoxDecoration(
              color: selected ? scheme.secondaryContainer : null,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(icon,
                    size: 18,
                    color: selected ? scheme.onSecondaryContainer : null),
                const SizedBox(width: 10),
                Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : null,
                      color: selected ? scheme.onSecondaryContainer : null,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IssueSummary extends StatelessWidget {
  final List<LibraryIssue> issues;
  const _IssueSummary({required this.issues});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counts = <String, int>{};
    for (final i in issues) {
      counts[i.kind] = (counts[i.kind] ?? 0) + 1;
    }
    const labels = {
      'adopted': '已认领',
      'orphan': '未登记',
      'missing': '文件缺失',
      'mismatch': '内容不符',
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('待处理',
              style: TextStyle(
                  fontSize: 11, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          ...counts.entries.map((e) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${labels[e.key] ?? e.key}  ${e.value}',
                  style: TextStyle(
                    fontSize: 12,
                    color: e.key == 'missing' || e.key == 'mismatch'
                        ? scheme.error
                        : scheme.onSurface,
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final LibraryController c;
  const _StatusBar({required this.c});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = c.lastError;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              error ?? c.status,
              style: TextStyle(
                fontSize: 12,
                color: error != null ? scheme.error : scheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (c.warming) ...[
            SizedBox(
              width: 90,
              child: LinearProgressIndicator(
                value: c.warmTotal == 0 ? null : c.warmDone / c.warmTotal,
                minHeight: 4,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '生成缩略图 ${c.warmDone}/${c.warmTotal}',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
