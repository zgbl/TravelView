import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

import '../state/account.dart';
import '../state/album_source.dart';
import '../state/story_draft.dart';
import '../widgets/share_sheet.dart';
import '../state/workspace.dart';

/// 发布：导出派生图 → 上传 → 拿到链接 → 分享。
///
/// **全程在手机上完成，不需要电脑在场。**
///
/// 两个阶段的进度分开报。导出是本地算力，上传是网络 ——
/// 用户卡在哪一步、该不该换个 Wi-Fi，只有分开报才看得出来。
class PublishPage extends StatefulWidget {
  final List<PhotoRecord> photos;
  final TripRoute route;
  final Account account;
  final StoryDraft draft;

  const PublishPage({
    super.key,
    required this.photos,
    required this.route,
    required this.account,
    required this.draft,
  });

  String get title => draft.effectiveTitle;

  @override
  State<PublishPage> createState() => _PublishPageState();
}

enum _Phase { exporting, uploading, done, failed }

class _PublishPageState extends State<PublishPage> {
  _Phase _phase = _Phase.exporting;
  String _label = '';
  int _done = 0, _total = 0;
  String? _error;
  PublishResult? _result;

  /// Story 已经在服务器上建好、图没传完时服务器给的 id。
  /// **必须留着** —— 重试时带上它是接着传那一篇，而不是又建一篇、又扣一次额度。
  String? _pendingStoryId;

  Directory? _exportDir;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _phase = _Phase.exporting;
      _error = null;
      _done = 0;
      _total = 0;
    });

    try {
      // ── 1. 导出派生图到临时工作目录 ──
      // 已经导过就不再导一遍：上传失败重试时，几百张图重新缩一次是纯浪费
      var dir = _exportDir;
      if (dir == null) {
        final out = Workspace.instance.exportDir(widget.title);
        await Workspace.instance.ensure(out);

        final exporter = StoryExporter(
          source: AlbumSource(widget.photos),
          outRoot: out,
        );
        final res = await exporter.export(
          trip: widget.route,
          selectedIds: widget.photos.map((p) => p.id).toSet(),
          heroByStopSeq: const {},
          legs: const [],
          title: widget.draft.effectiveTitle,
          subtitle: widget.draft.subtitle.trim().isEmpty
              ? null
              : widget.draft.subtitle.trim(),
          stopNames: widget.draft.names,
          stopNotes: widget.draft.notes,
          travelMode: widget.draft.travelMode,
          onProgress: (d, t, label) {
            if (mounted) {
              setState(() { _done = d; _total = t; _label = label; });
            }
          },
        );
        dir = res.dir;
        _exportDir = dir;
      }

      // ── 2. 上传 ──
      if (!mounted) return;
      setState(() {
        _phase = _Phase.uploading;
        _done = 0;
        _total = 0;
        _label = '';
      });

      final publisher = Publisher(widget.account.config);
      final result = await publisher.publish(
        dir,
        storyId: _pendingStoryId,
        onCreated: (id) => _pendingStoryId = id,
        onProgress: (d, t, label) {
          if (mounted) {
            setState(() { _done = d; _total = t; _label = label; });
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _Phase.done;
      });

      // 发布成功，派生图没有留着的理由了 —— 随时能重新生成，
      // 攒着不删会在用户手机上堆出几个 GB
      await Workspace.instance.dropStory(widget.title);
      _exportDir = null;
    } on PublishException catch (e) {
      if (e.storyId != null) _pendingStoryId = e.storyId;
      if (mounted) setState(() { _error = e.message; _phase = _Phase.failed; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _phase = _Phase.failed; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 传到一半退出去，那一篇会留在服务器上传了一半 —— 不拦，但要说清楚
      canPop: _phase != _Phase.uploading,
      child: Scaffold(
        appBar: AppBar(title: Text(tr('发布'))),
        body: switch (_phase) {
          _Phase.exporting => _progress(tr('正在准备照片'), tr('缩小、剥掉位置等元数据')),
          _Phase.uploading => _progress(tr('正在上传'), tr('断了可以接着传，不会重复扣额度')),
          _Phase.failed => _failed(),
          _Phase.done => _done_(),
        },
      ),
    );
  }

  Widget _progress(String title, String hint) {
    final pct = _total == 0 ? null : _done / _total;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 26),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: pct, minHeight: 8),
          ),
          const SizedBox(height: 12),
          Text(
            _total == 0 ? '' : '$_done / $_total   $_label',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12, color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _failed() => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off,
                size: 42, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 14),
            Text(_error ?? tr('发布失败'), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              _pendingStoryId == null
                  ? tr('还没开始上传，重试是从头来。')
                  : tr('已经传上去的部分不会重传，也不会重复扣额度。'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 52,
              width: double.infinity,
              child: FilledButton(
                  onPressed: _run, child: Text(tr('接着传'))),
            ),
          ],
        ),
      );

  Widget _done_() {
    final r = _result!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.check_circle,
              size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(r.updated ? tr('已更新') : tr('发布成功'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SelectableText(
            r.publicUrl,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: () =>
                  showShareSheet(context, r.publicUrl, title: widget.title),
              icon: const Icon(Icons.ios_share),
              label: Text(tr('分享')),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            // 分享到微信之后回不来是微信的老毛病（它会把自己顶到前台、
            // 接管整个任务栈）。**给一条不依赖分享面板的路**：
            // 复制链接，用户自己贴到任何地方去。
            child: OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: r.publicUrl));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr('链接已复制'))),
                  );
                }
              },
              icon: const Icon(Icons.link),
              label: Text(tr('复制链接')),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: TextButton(
              onPressed: () => Navigator.of(context)
                  .popUntil((route) => route.isFirst),
              child: Text(tr('回到首页')),
            ),
          ),
        ],
      ),
    );
  }
}
