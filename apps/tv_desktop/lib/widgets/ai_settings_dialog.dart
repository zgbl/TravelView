import 'package:flutter/material.dart';

import '../state/library_controller.dart';

/// AI 服务设置。
///
/// **用户自己付费，所以不该被绑死在某一家。** 用 OpenAI 兼容协议，
/// 换供应商只要改地址和模型名。key 只存在这台机器上。
class AiSettingsDialog extends StatefulWidget {
  final LibraryController c;
  const AiSettingsDialog({super.key, required this.c});

  static Future<void> show(BuildContext context, LibraryController c) =>
      showDialog(context: context, builder: (_) => AiSettingsDialog(c: c));

  @override
  State<AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<AiSettingsDialog> {
  late final base = TextEditingController(text: widget.c.settings.aiBaseUrl);
  late final key = TextEditingController(text: widget.c.settings.aiApiKey);
  late final model = TextEditingController(text: widget.c.settings.aiModel);
  late String language = widget.c.settings.aiLanguage;
  late String tone = widget.c.settings.aiTone;

  static const _presets = {
    'OpenAI': ['https://api.openai.com/v1', 'gpt-4o-mini'],
    'DeepSeek': ['https://api.deepseek.com/v1', 'deepseek-chat'],
    'Kimi': ['https://api.moonshot.cn/v1', 'moonshot-v1-8k'],
    '本地 Ollama': ['http://localhost:11434/v1', 'qwen2.5:7b'],
  };

  @override
  void dispose() {
    base.dispose();
    key.dispose();
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('AI 文案服务'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '用你自己的 AI 账号来起草文案，费用由你自己承担，'
                '我们不经手也不加价。\n'
                '任何兼容 OpenAI 接口的服务都能用，包括本机跑的模型。',
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant, height: 1.6),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: _presets.entries
                    .map((e) => ActionChip(
                          label: Text(e.key,
                              style: const TextStyle(fontSize: 12)),
                          onPressed: () => setState(() {
                            base.text = e.value[0];
                            model.text = e.value[1];
                          }),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: base,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: '接口地址',
                  helperText: '要带 /v1，例如 https://api.openai.com/v1',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: model,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: '模型',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: key,
                obscureText: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: 'API Key',
                  helperText: '只保存在这台电脑上，不会上传',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: language,
                      isDense: true,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(), labelText: '语言'),
                      items: const ['中文', 'English', '日本語']
                          .map((e) =>
                              DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(() => language = v ?? '中文'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: tone,
                      isDense: true,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(), labelText: '语气'),
                      items: const ['简洁克制', '生动一些', '像发朋友圈']
                          .map((e) =>
                              DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(() => tone = v ?? '简洁克制'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '发送给 AI 的只有文字: 地名、时间、停留时长、'
                  '照片张数、附近地标。**照片一张都不会发出去。**\n'
                  '不想联网也可以用「复制提示词」，自己粘到任何 AI 里。',
                  style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                      height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消')),
        FilledButton(
          onPressed: () {
            widget.c.settings
              ..aiBaseUrl = base.text.trim()
              ..aiApiKey = key.text.trim()
              ..aiModel = model.text.trim()
              ..aiLanguage = language
              ..aiTone = tone;
            widget.c.settings.save();
            Navigator.of(context).pop();
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
