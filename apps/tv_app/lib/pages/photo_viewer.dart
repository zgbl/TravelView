import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

import '../state/photo_source.dart';
import '../state/selection.dart';

/// 全屏看一张照片，左右滑翻页。
///
/// 桌面端的看图页有旋转、挑选、缩放、键盘导航一整套；这里**只有看**。
/// 手机上用户想编辑照片会去系统相册，那里的工具比我们做的任何东西都好用。
///
/// 加载的是 2K 的预览图而不是原件：原件可能是 40MB 的 HEIC、
/// 甚至还在 iCloud 上没下下来，为了看一眼去等它不值当。
class PhotoViewerPage extends StatefulWidget {
  final List<PhotoRecord> photos;
  final int index;

  /// 看大图的时候顺手勾选 —— **这才是挑图真正发生的地方。**
  /// 缩略图上分不出哪张更清楚、谁闭眼了，非得放大才看得出来。
  final TripSelection sel;

  const PhotoViewerPage(this.photos, this.index,
      {super.key, required this.sel});

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController _pc = PageController(initialPage: widget.index);
  late int _current = widget.index;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.photos[_current];
    final picked = widget.sel.has(p.id);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_current + 1} / ${widget.photos.length}',
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) => Opacity(
                opacity: widget.sel.has(widget.photos[i].id) ? 1 : 0.4,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: _FullPhoto(widget.photos[i].id),
                ),
              ),
            ),
          ),
          _Caption(p),
          _PickBar(
            picked: picked,
            onToggle: () => setState(() => widget.sel.toggle(p.id)),
          ),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  final PhotoRecord photo;
  const _Caption(this.photo);

  @override
  Widget build(BuildContext context) {
    final t = photo.takenAt;
    final time =
        '${t.year}.${t.month}.${t.day}  ${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(time,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 3),
          Text(
            photo.hasLocation
                ? '${photo.lat!.toStringAsFixed(4)}, '
                    '${photo.lon!.toStringAsFixed(4)}'
                : tr('这张没有位置信息'),
            style: TextStyle(
              color: photo.hasLocation ? Colors.white38 : Colors.orangeAccent,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// 全屏看图时的选中状态。
///
/// **按钮上写的是"现在是什么状态"，不是"点下去会怎样"。**
/// 写成"要这张"会让人以为还没选 —— 看的人分不清那是描述还是命令。
///
/// 横贯整个屏幕宽度、贴着底边：挑图要重复几百次，做成一整条，
/// 拇指随便往下一按就中，不用瞄。
class _PickBar extends StatelessWidget {
  final bool picked;
  final VoidCallback onToggle;
  const _PickBar({required this.picked, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: onToggle,
            style: FilledButton.styleFrom(
              backgroundColor: picked ? scheme.primary : scheme.surfaceContainerHighest,
              foregroundColor: picked ? scheme.onPrimary : scheme.onSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: Icon(picked ? Icons.check_circle : Icons.circle_outlined),
            label: Text(
              picked ? tr('已选') : tr('未选'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

class _FullPhoto extends StatefulWidget {
  final String assetId;
  const _FullPhoto(this.assetId);

  @override
  State<_FullPhoto> createState() => _FullPhotoState();
}

class _FullPhotoState extends State<_FullPhoto> {
  Uint8List? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = PhotoSource.instance.asset(widget.assetId);
    if (a == null) return;
    final bytes =
        await a.thumbnailDataWithSize(const ThumbnailSize(2048, 2048));
    if (bytes != null && mounted) setState(() => _data = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24),
        ),
      );
    }
    return Center(child: Image.memory(d, fit: BoxFit.contain));
  }
}
