import 'package:flutter/material.dart';

import '../state/library_controller.dart';
import '../state/l10n.dart';

/// 路径规划服务设置。
///
/// 界面上刻意**不出现供应商名字**给普通用户看 —— 用哪家是实现细节。
/// 但这是开发期的设置面板，所以把取舍讲清楚。
class RouteSettingsDialog extends StatefulWidget {
  final LibraryController c;
  const RouteSettingsDialog({super.key, required this.c});

  static Future<void> show(BuildContext context, LibraryController c) =>
      showDialog(context: context, builder: (_) => RouteSettingsDialog(c: c));

  @override
  State<RouteSettingsDialog> createState() => _RouteSettingsDialogState();
}

class _RouteSettingsDialogState extends State<RouteSettingsDialog> {
  late String provider = widget.c.settings.routeProvider;
  late final keyCtrl =
      TextEditingController(text: widget.c.settings.orsApiKey);
  late final urlCtrl =
      TextEditingController(text: widget.c.settings.osrmBaseUrl);

  @override
  void dispose() {
    keyCtrl.dispose();
    urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(tr('道路路线服务')),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('两个选项都基于 OpenStreetMap，结果允许永久保存 —— '
                  '这是能把路线写进分享页并十年后仍可显示的前提。\n'
                  '算过的路线会存进照片库的 catalog/routes.json，之后不再请求网络。'),
              style: TextStyle(
                  fontSize: 12, color: scheme.onSurfaceVariant, height: 1.6),
            ),
            const SizedBox(height: 18),
            RadioListTile<String>(
              value: 'ors',
              groupValue: provider,
              onChanged: (v) => setState(() => provider = v!),
              dense: true,
              title: Text(tr('openrouteservice（托管，起步最快）'),
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(tr('注册即有免费额度，适合现在用'),
                  style: const TextStyle(fontSize: 11)),
            ),
            if (provider == 'ors')
              Padding(
                padding: const EdgeInsets.fromLTRB(52, 0, 8, 8),
                child: TextField(
                  controller: keyCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    labelText: 'API key',
                    hintText: tr('在 openrouteservice.org 注册后获取'),
                  ),
                ),
              ),
            RadioListTile<String>(
              value: 'osrm',
              groupValue: provider,
              onChanged: (v) => setState(() => provider = v!),
              dense: true,
              title: Text(tr('OSRM（自托管，长期首选）'),
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(tr('没有额度限制，但预处理路网很吃内存'),
                  style: const TextStyle(fontSize: 11)),
            ),
            if (provider == 'osrm')
              Padding(
                padding: const EdgeInsets.fromLTRB(52, 0, 8, 8),
                child: TextField(
                  controller: urlCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    labelText: tr('服务地址'),
                    hintText: 'http://localhost:5000',
                  ),
                ),
              ),
            RadioListTile<String>(
              value: 'direct',
              groupValue: provider,
              onChanged: (v) => setState(() => provider = v!),
              dense: true,
              title: Text(tr('只用直线'), style: const TextStyle(fontSize: 13)),
              subtitle: Text(tr('不联网。任何服务不可用时的兜底'),
                  style: const TextStyle(fontSize: 11)),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tr('为什么没有 Google：它的条款既限制存储路线内容，'
                    '又要求路线必须显示在 Google 地图上，不能与其它底图混用。'
                    '我们用的是自托管底图，两条都冲突。'),
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurfaceVariant, height: 1.5),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('取消'))),
        FilledButton(
          onPressed: () {
            widget.c.settings
              ..routeProvider = provider
              ..orsApiKey = keyCtrl.text.trim()
              ..osrmBaseUrl = urlCtrl.text.trim();
            widget.c.settings.save();
            Navigator.of(context).pop();
          },
          child: Text(tr('保存')),
        ),
      ],
    );
  }
}
