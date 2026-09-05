import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:tv_core/tv_core.dart';

import '../state/library_controller.dart';
import 'phone_import_page.dart';
import '../widgets/photo_tile.dart';
import '../widgets/stat_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final c = LibraryController();

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
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: c.hasLibrary ? _libraryView(context) : _emptyState(context),
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
          child: days.isEmpty
              ? _noPhotos(context)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
                  itemCount: days.length,
                  itemBuilder: (context, i) =>
                      _DaySection(c: c, entry: days[i]),
                ),
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

  const _Sidebar({
    required this.c,
    required this.onOpen,
    required this.onImport,
    required this.onPhoneImport,
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

  const _Action({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 10),
                Text(label, style: const TextStyle(fontSize: 13)),
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

class _DaySection extends StatelessWidget {
  final LibraryController c;
  final MapEntry<String, List<PhotoRecord>> entry;

  const _DaySection({required this.c, required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(entry.key,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Text('${entry.value.length} 张',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: entry.value
                .map((r) => PhotoTile(
                      record: r,
                      file: c.fileOf(r),
                      thumbs: c.thumbs!,
                    ))
                .toList(),
          ),
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
      alignment: Alignment.centerLeft,
      child: Text(
        error ?? c.status,
        style: TextStyle(
          fontSize: 12,
          color: error != null ? scheme.error : scheme.onSurfaceVariant,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
