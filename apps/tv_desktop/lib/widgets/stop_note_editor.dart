import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tv_core/tv_core.dart';

import '../state/library_controller.dart';

/// 一站的文字。
///
/// 设计上有个明确的立场: **文字是用户的，AI 只是起草。**
/// 所以生成的结果直接落进可编辑的输入框，而不是弹个对话框让人"接受/拒绝"；
/// 用户改一个字，来源就从 ai 变成 aiEdited。
class StopNoteEditor extends StatefulWidget {
  final LibraryController c;
  final TripRoute trip;
  final Stop stop;

  const StopNoteEditor({
    super.key,
    required this.c,
    required this.trip,
    required this.stop,
  });

  @override
  State<StopNoteEditor> createState() => _StopNoteEditorState();
}

class _StopNoteEditorState extends State<StopNoteEditor> {
  late final TextEditingController title;
  late final TextEditingController note;
  final hint = TextEditingController();
  String source = 'user';
  bool expanded = false;
  bool lookingUp = false;
  bool drafting = false;

  @override
  void initState() {
    super.initState();
    final n = widget.c.noteOf(widget.stop);
    title = TextEditingController(text: n?.title ?? '');
    note = TextEditingController(text: n?.note ?? '');
    source = n?.source ?? 'user';
  }

  @override
  void dispose() {
    title.dispose();
    note.dispose();
    hint.dispose();
    super.dispose();
  }

  void _save({String? newSource}) {
    widget.c.saveNote(
      widget.stop,
      StopNote(
        title: title.text,
        note: note.text,
        source: newSource ?? source,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _onEdited() {
    // 用户动过自动生成的稿子，来源要如实记下来 ——
    // 否则下次"批量生成"就分不清哪些是他亲手写的，可能覆盖掉
    final next = source == 'ai'
        ? 'aiEdited'
        : source == 'facts'
            ? 'factsEdited'
            : source;
    if (next != source) setState(() => source = next);
    _save(newSource: next);
  }

  Future<void> _lookup() async {
    setState(() => lookingUp = true);
    await widget.c.lookupPlace(widget.stop);
    if (mounted) setState(() => lookingUp = false);
  }

  /// Level 1: 直接用已知的时间和地理信息写一句话，不联 AI。
  Future<void> _autoFill() async {
    setState(() => drafting = true);
    final cap = await widget.c.factCaption(widget.stop, widget.trip);
    if (!mounted) return;
    setState(() {
      drafting = false;
      if (title.text.trim().isEmpty) title.text = cap.title;
      note.text = cap.text;
      source = 'facts';
    });
    _save(newSource: 'facts');
  }

  Future<void> _copyPrompt() async {
    await widget.c.lookupPlace(widget.stop);
    final p = widget.c.buildPrompt(widget.stop, widget.trip,
        userHint: hint.text);
    await Clipboard.setData(ClipboardData(text: p));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('提示词已复制，粘贴到任意 AI 里即可'),
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _draft() async {
    final draft = await widget.c.draftNote(widget.stop, widget.trip,
        userHint: hint.text);
    if (!mounted) return;
    if (draft == null) {
      final err = widget.c.aiError;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('AI 生成失败: $err')));
      }
      return;
    }
    setState(() {
      if (draft.title.isNotEmpty) title.text = draft.title;
      note.text = draft.note;
      source = 'ai';
    });
    _save(newSource: 'ai');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final place = widget.c.placeOf(widget.stop);
    final aiReady = widget.c.aiConfig.isConfigured &&
        widget.c.settings.aiApiKey.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text('这一站的文字',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary)),
              const SizedBox(width: 10),
              if (place?.primary != null)
                Text(place!.names.join(' / '),
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant))
              else
                TextButton(
                  onPressed: lookingUp ? null : _lookup,
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: Size.zero),
                  child: Text(lookingUp ? '查询中...' : '查地名和附近地标',
                      style: const TextStyle(fontSize: 11)),
                ),
              const Spacer(),
              if (source != 'user')
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(_sourceLabel(source),
                      style: TextStyle(
                          fontSize: 9, color: scheme.onTertiaryContainer)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: title,
            onChanged: (_) => _onEdited(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: '小标题',
              hintText: '例如 河上的一小时',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: note,
            onChanged: (_) => _onEdited(),
            maxLines: 4,
            minLines: 2,
            style: const TextStyle(fontSize: 13, height: 1.5),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: '说明文字',
              hintText: '写几句，或者让 AI 起个草再改',
            ),
          ),
          const SizedBox(height: 8),
          if (expanded) ...[
            TextField(
              controller: hint,
              maxLines: 2,
              minLines: 1,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: '给 AI 的补充信息（可选）',
                hintText: '例如: 坐了游船，风很大，和爸妈一起',
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => expanded = !expanded),
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 15),
                label: Text(expanded ? '收起' : '补充信息',
                    style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 4),
              drafting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : FilledButton.tonalIcon(
                      onPressed: _autoFill,
                      icon: const Icon(Icons.bolt, size: 14),
                      label: const Text('自动生成',
                          style: TextStyle(fontSize: 12)),
                    ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _copyPrompt,
                icon: const Icon(Icons.content_copy, size: 14),
                label: const Text('复制提示词', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              widget.c.aiBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : FilledButton.tonalIcon(
                      onPressed: aiReady ? _draft : null,
                      icon: const Icon(Icons.auto_awesome, size: 14),
                      label: const Text('用我的 AI 起草',
                          style: TextStyle(fontSize: 12)),
                    ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  aiReady
                      ? '只发送地名、时间、地标等文字，照片不会发出去'
                      : '需要先在设置里填自己的 AI 服务（费用由你自己承担）',
                  style: TextStyle(
                      fontSize: 10, color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _sourceLabel(String s) {
    switch (s) {
      case 'ai':
        return 'AI 起草';
      case 'aiEdited':
        return 'AI 起草后已修改';
      case 'facts':
        return '按时间地点自动生成';
      case 'factsEdited':
        return '自动生成后已修改';
      default:
        return '手写';
    }
  }
}
