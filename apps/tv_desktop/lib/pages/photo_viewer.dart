import 'dart:io';

// PointerScrollEvent / PointerPanZoom* 都在 gestures 里，
// material 只 re-export 了 gestures 的一小部分（DragStartBehavior 之类）
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:tv_core/tv_core.dart';

import '../state/library_controller.dart';
import '../widgets/photo_tile.dart';

const _videoExt = {'.mov', '.mp4', '.m4v', '.avi'};

/// 全图查看。
///
/// HEIC 在 Flutter 里解不了，所以和缩略图一样走系统解码（ImageIO），
/// 只是尺寸更大（2400px），缓存在 catalog/previews/。
/// 视频不内嵌播放 —— 显示首帧，需要看就交给系统播放器。
class PhotoViewer extends StatefulWidget {
  final LibraryController c;
  final List<PhotoRecord> photos;
  final int initialIndex;

  const PhotoViewer({
    super.key,
    required this.c,
    required this.photos,
    required this.initialIndex,
  });

  static Future<void> open(
    BuildContext context, {
    required LibraryController c,
    required List<PhotoRecord> photos,
    required int index,
  }) {
    // opaque: true —— 透明路由在 macOS 的 Impeller 后端上会整片渲染成黑色，
    // 而我们本来就是不透明的黑底，不需要透明。
    return Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      fullscreenDialog: true,
      pageBuilder: (_, __, ___) =>
          PhotoViewer(c: c, photos: photos, initialIndex: index),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 120),
    ));
  }

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late int index = widget.initialIndex;
  final _transform = TransformationController();
  bool showInfo = true;

  /// 刚刚改过选取状态的时刻，用来闪一下提示，让"到底选上没有"一目了然
  DateTime? _pickFlash;

  /// 手动重新生成预览时用来强制刷新 FutureBuilder
  int _reloadToken = 0;

  /// 滚动翻页的累积量。
  ///
  /// 平台习惯不同，不能一视同仁:
  ///   - macOS: Magic Mouse 鼠标背**左右**滑 / 触控板双指左右滑 -> 翻页；
  ///     上下滑不翻页（上下是"看这一张"的动作，翻页是横向的）
  ///   - Windows: 滚轮只有上下，那就用上下翻页
  double _scrollAccum = 0;
  DateTime _lastFlip = DateTime.fromMillisecondsSinceEpoch(0);
  static const _flipThreshold = 45.0;
  static const _flipCooldown = Duration(milliseconds: 180);

  /// **必须从 catalog 取最新的记录**。
  /// widget.photos 是打开查看器那一刻的快照，打完标签后它不会变，
  /// 用它判断选中状态会永远显示"未选取"。
  PhotoRecord get current {
    final snap = widget.photos[index];
    return widget.c.catalog?.byId(_liveId(snap.id)) ?? snap;
  }

  /// 旋转会改变内容哈希从而换新 id，这里记录 旧id -> 新id 的映射
  final _idRemap = <String, String>{};
  String _liveId(String id) => _idRemap[id] ?? id;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = index + delta;
    if (next < 0 || next >= widget.photos.length) return;
    setState(() {
      index = next;
      _transform.value = Matrix4.identity();
      _scrollAccum = 0;
    });
  }

  bool get _zoomed => _transform.value.getMaxScaleOnAxis() > 1.05;

  /// 放大状态下滚动是平移图片，不翻页 —— 否则看局部时会乱跳。
  void _onScrollDelta(double dx, double dy) {
    if (_zoomed) return;
    // macOS 只认横向，Windows/Linux 只认纵向 —— 各自符合本平台的手感
    final delta = Platform.isMacOS ? dx : dy;
    if (delta == 0) return;

    final now = DateTime.now();
    if (now.difference(_lastFlip) < _flipCooldown) return;

    _scrollAccum += delta;
    if (_scrollAccum.abs() < _flipThreshold) return;

    final forward = _scrollAccum > 0;
    _scrollAccum = 0;
    _lastFlip = now;
    _go(forward ? 1 : -1);
  }

  void _toggleZoom() {
    setState(() {
      _transform.value =
          _zoomed ? Matrix4.identity() : (Matrix4.identity()..scale(2.5));
    });
  }

  void _zoomBy(double factor) {
    final cur = _transform.value.getMaxScaleOnAxis();
    final next = (cur * factor).clamp(1.0, 6.0);
    setState(() => _transform.value = Matrix4.identity()..scale(next));
  }

  /// 旋转 90 度，直接写回原文件（无损，不改拍摄时间）
  Future<void> _rotate(bool clockwise) async {
    final snap = widget.photos[index];
    final live = current;
    final newId = await widget.c.rotate(live, clockwise: clockwise);
    if (!mounted) return;
    if (newId != null) _idRemap[snap.id] = newId;
    setState(() {});
  }

  /// 选取/取消选取。**不翻页** —— 停在原地才能看清有没有选上。
  /// 不选取只是不进这个专辑，照片一直在库里。
  Future<void> _togglePick() async {
    await widget.c.togglePick(current);
    if (!mounted) return;
    setState(() => _pickFlash = DateTime.now());
  }

  Future<void> _setPick(bool on) async {
    await widget.c.setPicked(current, on);
    if (!mounted) return;
    setState(() => _pickFlash = DateTime.now());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    switch (e.logicalKey) {
      // 选取与翻页彻底分开: 按了空格只改选取状态，停在原地让你看清结果，
      // 也方便反悔再按一次。翻页用方向键或滑动。
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.keyP:
        _togglePick();
      case LogicalKeyboardKey.keyX:
      case LogicalKeyboardKey.backspace:
        _setPick(false);
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowDown:
        _go(1);
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowUp:
        _go(-1);
      case LogicalKeyboardKey.home:
        setState(() => index = 0);
      case LogicalKeyboardKey.end:
        setState(() => index = widget.photos.length - 1);
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
      case LogicalKeyboardKey.bracketRight:
        _rotate(true);
      case LogicalKeyboardKey.bracketLeft:
        _rotate(false);
      case LogicalKeyboardKey.keyZ:
        _toggleZoom();
      case LogicalKeyboardKey.keyI:
        setState(() => showInfo = !showInfo);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        // Esc 单独挂在这里 —— 即使下面的 Focus 没拿到键盘，也一定关得掉
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: const Color(0xFF0E0E10),
        // fit: StackFit.expand 是必须的！
        // Stack 只有在"没有任何非定位子组件"时才会自己撑满；一旦出现一个
        // 非定位子组件（_pickToast 大多数时候返回 SizedBox.shrink，就是 0x0），
        // Stack 就会缩成 0x0，所有 Positioned.fill 的内容随之消失 —— 整片全黑。
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Listener(
                onPointerSignal: (e) {
                  if (e is! PointerScrollEvent) return;
                  final keys = HardwareKeyboard.instance;
                  if (keys.isMetaPressed || keys.isControlPressed) {
                    _zoomBy(e.scrollDelta.dy > 0 ? 0.9 : 1.1);
                    return;
                  }
                  _onScrollDelta(e.scrollDelta.dx, e.scrollDelta.dy);
                },
                // 触控板的双指滑动在 macOS 上走 pan/zoom 事件
                onPointerPanZoomStart: (_) => _scrollAccum = 0,
                onPointerPanZoomUpdate: (e) =>
                    _onScrollDelta(-e.panDelta.dx, -e.panDelta.dy),
                child: _stage(),
              ),
            ),
            Positioned.fill(child: _pickFrame()),
            _topBar(),
            if (index > 0) _navButton(left: true),
            if (index < widget.photos.length - 1) _navButton(left: false),
            if (showInfo) _infoPanel(),
            Positioned.fill(child: _pickToast()),
            _bottomBar(),
          ],
        ),
      ),
      ),
    );
  }

  Widget _stage() {
    final rec = current;
    final file = widget.c.fileOf(rec);
    final isVideo = _videoExt.contains(p.extension(file.path).toLowerCase());

    return FutureBuilder<File?>(
      // key 保证切换照片时重新取图，而不是复用上一张的 Future
      key: ValueKey('${rec.id}/$_reloadToken'),
      future: widget.c.thumbs!.preview(rec.id, file),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        }
        if (snap.hasError) {
          return _failure('生成预览时出错', '${snap.error}', file);
        }
        final f = snap.data;
        if (f == null) {
          return _failure('无法为这个文件生成预览', rec.origFilename, file);
        }

        final image = GestureDetector(
          onDoubleTap: _toggleZoom,
          child: InteractiveViewer(
            transformationController: _transform,
            minScale: 1,
            maxScale: 6,
            scaleEnabled: false,
            panEnabled: true,
            child: Center(
              child: Image.file(
                f,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                // 之前这里没有 errorBuilder —— 预览图损坏时 Flutter 什么都不画，
                // 表现就是"一片黑"，完全看不出发生了什么
                errorBuilder: (context, err, stack) =>
                    _failure('预览图读不出来', '$err', file, badPreview: f),
              ),
            ),
          ),
        );
        if (!isVideo) return image;
        return Stack(
          alignment: Alignment.center,
          children: [image, _playOverlay(file)],
        );
      },
    );
  }

  /// 出问题时给出可操作的信息，而不是一片黑
  Widget _failure(String title, String detail, File source,
      {File? badPreview}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined,
                size: 44, color: Colors.white38),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            const SizedBox(height: 8),
            SelectableText(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 6),
            SelectableText(
              source.path,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _regenerate(badPreview),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重新生成预览'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _openWithSystem(source),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('用系统程序打开原图'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 删掉坏掉的预览图并重来。缓存是派生数据，删了随时能重建。
  Future<void> _regenerate(File? badPreview) async {
    final rec = current;
    final th = widget.c.thumbs!;
    for (final f in [badPreview, th.pathFor(rec.id, variant: 'previews')]) {
      if (f != null && await f.exists()) {
        await f.delete();
      }
    }
    th.forget(rec.id, variant: 'previews');
    // 让 Flutter 的图片缓存也忘掉这个文件，否则会继续拿旧的坏数据
    imageCache.clear();
    imageCache.clearLiveImages();
    if (mounted) setState(() => _reloadToken++);
  }

  Widget _playOverlay(File file) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: () => _openWithSystem(file),
          icon: const Icon(Icons.play_arrow),
          label: const Text('用系统播放器打开'),
        ),
        const SizedBox(height: 10),
        const Text('视频暂不内嵌播放，这里显示的是首帧',
            style: TextStyle(color: Colors.white60, fontSize: 12)),
      ],
    );
  }

  Widget _topBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
        color: Colors.black.withValues(alpha: 0.45),
        // ExcludeFocus: 否则按钮拿到焦点后，空格会去"点按钮"而不是选取照片
        child: ExcludeFocus(
          child: Row(
          children: [
            Text(
              '${index + 1} / ${widget.photos.length}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                current.origFilename,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _pickButton(),
            const SizedBox(width: 10),
            IconButton(
              tooltip: '向左旋转 (  [  )',
              onPressed: () => _rotate(false),
              icon: const Icon(Icons.rotate_left, color: Colors.white70),
            ),
            IconButton(
              tooltip: '向右旋转 (  ]  )',
              onPressed: () => _rotate(true),
              icon: const Icon(Icons.rotate_right, color: Colors.white70),
            ),
            IconButton(
              tooltip: '在访达中显示',
              onPressed: () => _revealInFinder(widget.c.fileOf(current)),
              icon: const Icon(Icons.folder_open, color: Colors.white70),
            ),
            IconButton(
              tooltip: '用默认程序打开原图',
              onPressed: () => _openWithSystem(widget.c.fileOf(current)),
              icon: const Icon(Icons.open_in_new, color: Colors.white70),
            ),
            IconButton(
              tooltip: '信息 (I)',
              onPressed: () => setState(() => showInfo = !showInfo),
              icon: Icon(Icons.info_outline,
                  color: showInfo ? Colors.white : Colors.white54),
            ),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('关闭'),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _pickButton() {
    final picked = widget.c.isPicked(current);
    return Tooltip(
      message: picked ? '已在「${widget.c.pickAlbum}」中 (X 移出)' : '加入「${widget.c.pickAlbum}」(空格)',
      child: FilledButton.icon(
        onPressed: () => _togglePick(),
        style: FilledButton.styleFrom(
          backgroundColor:
              picked ? const Color(0xFF2E6F6A) : Colors.white24,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        icon: Icon(picked ? Icons.check_circle : Icons.circle_outlined,
            size: 18),
        label: Text(picked ? '已选取' : '未选取'),
      ),
    );
  }

  /// 选中时给整幅图加一圈边框 —— 连续翻页时不用去看按钮就知道状态
  Widget _pickFrame() {
    if (!widget.c.isPicked(current)) return const SizedBox.shrink();
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF4FBFA8), width: 4),
        ),
      ),
    );
  }

  /// 刚按下选取键时，在画面中央闪一个大提示。
  /// 因为按键不再自动翻页，必须让"选上了/取消了"这件事非常明确。
  Widget _pickToast() {
    final at = _pickFlash;
    if (at == null) return const SizedBox.shrink();
    if (DateTime.now().difference(at) > const Duration(milliseconds: 1100)) {
      return const SizedBox.shrink();
    }
    final picked = widget.c.isPicked(current);
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          key: ValueKey(at),
          tween: Tween(begin: 1, end: 0),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeIn,
          onEnd: () {
            if (mounted) setState(() => _pickFlash = null);
          },
          builder: (context, v, child) =>
              Opacity(opacity: v.clamp(0, 1), child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  picked ? Icons.check_circle : Icons.remove_circle_outline,
                  size: 40,
                  color: picked ? const Color(0xFF4FBFA8) : Colors.white70,
                ),
                const SizedBox(height: 8),
                Text(
                  picked ? '已加入「${widget.c.pickAlbum}」' : '已移出',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        color: Colors.black.withValues(alpha: 0.45),
        child: ExcludeFocus(
          child: Row(
          children: [
            Icon(Icons.check_circle,
                size: 15, color: const Color(0xFF4FBFA8)),
            const SizedBox(width: 6),
            Text(
              '「${widget.c.pickAlbum}」已选 ${widget.c.pickedCount} 张',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            const Spacer(),
            Text(
              '空格 选取/取消   X 移出   '
              '[ ] 旋转   Z 缩放   '
              '${Platform.isMacOS ? "左右滑动" : "滚轮"} 翻页   Esc 关闭',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _navButton({required bool left}) {
    return Positioned(
      left: left ? 16 : null,
      right: left ? null : 16,
      top: 0,
      bottom: 0,
      child: Center(
        child: IconButton.filledTonal(
          onPressed: () => _go(left ? -1 : 1),
          icon: Icon(left ? Icons.chevron_left : Icons.chevron_right),
          iconSize: 28,
        ),
      ),
    );
  }

  Widget _infoPanel() {
    final r = current;
    final rows = <String, String>{
      '拍摄时间':
          '${LibraryLayout.dateStamp(r.takenAt)} ${LibraryLayout.timeStamp(r.takenAt)}',
      if (r.hasLocation)
        '位置': '${r.lat!.toStringAsFixed(5)}, ${r.lon!.toStringAsFixed(5)}'
      else
        '位置': '无 GPS',
      if (r.width != null && r.height != null)
        '尺寸': '${r.width} x ${r.height}',
      '大小': humanBytes(r.bytes),
      if (r.device != null) '设备': r.device!,
      '库内路径': widget.c.catalog?.relPathOf(r.id) ?? '',
    };
    return Positioned(
      right: 16,
      bottom: 56,
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: rows.entries
              .map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 66,
                          child: Text(e.key,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11)),
                        ),
                        Expanded(
                          child: SelectableText(
                            e.value,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  /// 原图交给系统处理 —— 只读打开，不做任何修改
  Future<void> _openWithSystem(File f) async {
    if (Platform.isMacOS) {
      await Process.run('open', [f.path]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', f.path]);
    }
  }

  Future<void> _revealInFinder(File f) async {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', f.path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,${f.path}']);
    }
  }
}
