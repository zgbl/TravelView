import 'package:flutter/material.dart';

import '../state/library_controller.dart';
import '../state/projects.dart';

/// 工作进度条：保存 / 打开 / 删除命名草稿。
///
/// 草稿存在照片库里（`catalog/projects.json`），把库拷走进度也跟着走。
class ProjectBar extends StatelessWidget {
  final LibraryController c;
  const ProjectBar({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
      children: [
        Icon(Icons.bookmark_border, size: 16, color: scheme.primary),
        const SizedBox(width: 8),
        Text(
          c.currentProjectName ?? '未保存的工作',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: c.currentProjectName == null
                ? scheme.onSurfaceVariant
                : scheme.onSurface,
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.tonalIcon(
          onPressed: () => _save(context),
          icon: const Icon(Icons.save_outlined, size: 15),
          label: Text(c.currentProjectName == null ? '保存工作进度' : '保存',
              style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: c.projects.isEmpty ? null : () => _open(context),
          icon: const Icon(Icons.folder_open_outlined, size: 15),
          label: Text('打开（${c.projects.length}）',
              style: const TextStyle(fontSize: 12)),
        ),
        if (c.currentProjectName != null) ...[
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _saveAs(context),
            icon: const Icon(Icons.copy_all_outlined, size: 15),
            label: const Text('另存为', style: TextStyle(fontSize: 12)),
          ),
        ],
      ],
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final name = c.currentProjectName;
    if (name != null) {
      await c.saveProject(name);
      return;
    }
    await _saveAs(context);
  }

  Future<void> _saveAs(BuildContext context) async {
    final controller = TextEditingController(
        text: c.currentProjectName ?? _suggestName());
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存工作进度'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '保存当前的时间范围、挑选专辑、视图和聚类粒度。\n'
                '下次打开可以直接接着做。',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '名字',
                  hintText: '例如 横穿美国 2025',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) => Navigator.of(ctx).pop(v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await c.saveProject(name);
    }
  }

  String _suggestName() {
    final s = c.rangeStart;
    if (s == null) return '全部照片';
    return '${s.year}-${s.month.toString().padLeft(2, '0')} 的行程';
  }

  Future<void> _open(BuildContext context) async {
    final proj = await showDialog<Project>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('打开工作进度'),
        children: [
          SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: c.projects
                  .map((p) => ListTile(
                        leading: const Icon(Icons.bookmark_outline),
                        title: Text(p.name),
                        subtitle: Text(_describe(p),
                            style: const TextStyle(fontSize: 11)),
                        trailing: IconButton(
                          tooltip: '删除这份进度（不影响照片）',
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () async {
                            await c.deleteProject(p);
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          },
                        ),
                        onTap: () => Navigator.of(ctx).pop(p),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
    if (proj != null) await c.openProject(proj);
  }

  static String _describe(Project p) {
    final a = p.rangeStart, b = p.rangeEnd;
    final range = (a == null && b == null)
        ? '全部照片'
        : '${_fmt(a)} ~ ${_fmt(b)}';
    return '$range   专辑「${p.pickAlbum}」';
  }

  static String _fmt(DateTime? t) {
    if (t == null) return '不限';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}
