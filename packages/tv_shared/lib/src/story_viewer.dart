import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:tv_core/tv_core.dart';

import 'l10n.dart';
import 'story_bundle.dart';

/// **在 App 里把自己做的行程看一遍。** 桌面端和手机端同一份。
///
/// 为什么不内嵌一个 WebView 去开导出的 index.html：
///   - macOS / Windows 上没有一个轻量可靠的 WebView，为了看一眼自己的游记
///     拖进来一个浏览器内核不划算；
///   - 网页那份要联网取 Leaflet 和底图，而"看自己刚做完的东西"
///     恰恰最可能发生在没网的路上、飞机上。
///
/// 代价是渲染有两份（网页一份、原生一份），所以这里**只呈现 manifest 里有的东西**，
/// 不自己算任何数据 —— 两边要是显示不一样，那也只能是样式不一样，不会是数字不一样。
class StoryViewerPage extends StatefulWidget {
  final StoryBundle bundle;

  /// 右上角的分享动作。没传就不显示 —— 本地还没发布的产物没什么可分享的。
  final void Function(BuildContext context, String url)? onShare;

  const StoryViewerPage({super.key, required this.bundle, this.onShare});

  /// 从任意地方打开一篇故事。加载和出错都在这里处理完，
  /// 调用方只管说"打开这个"。
  static Future<void> open(
    BuildContext context,
    Future<StoryBundle> Function() load, {
    void Function(BuildContext context, String url)? onShare,
  }) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _StoryLoaderPage(load: load, onShare: onShare),
    ));
  }

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage> {
  StoryBundle get b => widget.bundle;
  Story get s => b.story;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final share = b.shareUrl;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            stretch: true,
            foregroundColor: Colors.white,
            backgroundColor: scheme.surface,
            actions: [
              if (share != null && widget.onShare != null)
                IconButton(
                  tooltip: tr('分享'),
                  icon: const Icon(Icons.ios_share),
                  onPressed: () => widget.onShare!(context, share),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: _Cover(bundle: b),
            ),
          ),
          SliverToBoxAdapter(child: _Header(bundle: b)),
          if (s.stops.length > 1)
            SliverToBoxAdapter(child: _OverviewMap(bundle: b)),
          ..._daySlivers(context),
          SliverToBoxAdapter(child: _Summary(bundle: b)),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  /// 按天分组，天下面是站。
  ///
  /// **没有 days 的老产物也要能看**：那时就把所有站铺平，
  /// 打不开一篇旧游记比少一个日期标题严重得多。
  List<Widget> _daySlivers(BuildContext context) {
    final byId = {for (final st in s.stops) st.id: st};
    final out = <Widget>[];

    if (s.days.isEmpty) {
      for (final st in s.stops) {
        out.add(SliverToBoxAdapter(child: _StopSection(bundle: b, stop: st)));
      }
      return out;
    }

    for (final day in s.days) {
      out.add(SliverToBoxAdapter(child: _DayHeader(day: day)));
      for (final id in day.stopIds) {
        final st = byId[id];
        if (st == null) continue;
        out.add(SliverToBoxAdapter(child: _StopSection(bundle: b, stop: st)));
      }
    }
    return out;
  }
}

/// 打开中 / 打开失败的那一屏。
class _StoryLoaderPage extends StatefulWidget {
  final Future<StoryBundle> Function() load;
  final void Function(BuildContext context, String url)? onShare;
  const _StoryLoaderPage({required this.load, this.onShare});

  @override
  State<_StoryLoaderPage> createState() => _StoryLoaderPageState();
}

class _StoryLoaderPageState extends State<_StoryLoaderPage> {
  StoryBundle? _bundle;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _error = null);
    try {
      final b = await widget.load();
      if (mounted) setState(() => _bundle = b);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is StoryBundleException ? e.message : '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _bundle;
    if (b != null) return StoryViewerPage(bundle: b, onShare: widget.onShare);

    return Scaffold(
      appBar: AppBar(title: Text(tr('打开行程'))),
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off,
                        size: 40,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: _run, child: Text(tr('重试'))),
                  ],
                ),
              ),
      ),
    );
  }
}

// ───────────────────────── 封面 ─────────────────────────

class _Cover extends StatelessWidget {
  final StoryBundle bundle;
  const _Cover({required this.bundle});

  @override
  Widget build(BuildContext context) {
    final photo = bundle.coverPhoto;
    return Stack(fit: StackFit.expand, children: [
      if (photo != null)
        Image(
          image: bundle.full(photo),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12),
        )
      else
        const ColoredBox(color: Colors.black12),
      // 压一层渐变，白字才读得出来。**不要靠照片本身够暗**
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.center,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black87],
          ),
        ),
      ),
      Positioned(
        left: 20,
        right: 20,
        bottom: 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              bundle.story.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            if ((bundle.story.subtitle ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(bundle.story.subtitle!,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ],
        ),
      ),
    ]);
  }
}

class _Header extends StatelessWidget {
  final StoryBundle bundle;
  const _Header({required this.bundle});

  @override
  Widget build(BuildContext context) {
    final s = bundle.story;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        '${_d(s.start)} — ${_d(s.end)}',
        style: TextStyle(fontSize: 12, color: scheme.outline),
      ),
    );
  }
}

String _d(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

String _hm(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}';
}

// ───────────────────────── 概览地图 ─────────────────────────

/// 整趟路线的一张图。
///
/// **底图取不到也要能看**：路线和站点是本地数据，画在空白底上照样成立；
/// 在飞机上、在没信号的山里打开自己刚做的游记，看到的不该是一块灰。
class _OverviewMap extends StatelessWidget {
  final StoryBundle bundle;
  const _OverviewMap({required this.bundle});

  @override
  Widget build(BuildContext context) {
    final s = bundle.story;
    final scheme = Theme.of(context).colorScheme;

    // 有真实路网就用路网，没有就用轨迹点，再没有就连站点 —— 和网页同一个优先级
    final line = <ll.LatLng>[];
    for (final r in s.routes) {
      for (final p in PolylineCodec.decode(r.encodedGeometry,
          precision: r.precision)) {
        line.add(ll.LatLng(p.lat, p.lon));
      }
    }
    if (line.isEmpty) {
      for (final p in s.path) {
        line.add(ll.LatLng(p.lat, p.lon));
      }
    }
    if (line.isEmpty) {
      for (final st in s.stops) {
        line.add(ll.LatLng(st.lat, st.lon));
      }
    }
    if (line.isEmpty) return const SizedBox.shrink();

    final bounds = LatLngBounds.fromPoints(line);

    return Container(
      height: 220,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: scheme.surfaceContainerHighest,
      ),
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit:
              CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(28)),
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'app.travelview',
            // 没网时静静地留白，不要摆一排碎图图标
            errorTileCallback: (_, __, ___) {},
          ),
          PolylineLayer(polylines: [
            Polyline(
                points: line, strokeWidth: 3.5, color: scheme.primary),
          ]),
          MarkerLayer(markers: [
            for (final st in s.stops)
              Marker(
                point: ll.LatLng(st.lat, st.lon),
                width: 20,
                height: 20,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ]),
        ],
      ),
    );
  }
}

// ───────────────────────── 每天 / 每站 ─────────────────────────

class _DayHeader extends StatelessWidget {
  final StoryDay day;
  const _DayHeader({required this.day});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 6),
      child: Row(children: [
        Text(day.date,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.primary)),
        if ((day.label ?? '').isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(day.label!,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.outline)),
          ),
        ],
      ]),
    );
  }
}

class _StopSection extends StatelessWidget {
  final StoryBundle bundle;
  final StoryStop stop;
  const _StopSection({required this.bundle, required this.stop});

  /// 界面是英文就用英文那份，没有英文就退回中文 —— **不留空**。
  String? _localized(String? zh, String? en) {
    if (L10n.isEn) {
      final e = en?.trim();
      if (e != null && e.isNotEmpty) return e;
    }
    final z = zh?.trim();
    return (z == null || z.isEmpty) ? null : z;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = _localized(stop.name, stop.nameEn);
    final note = _localized(stop.note, stop.noteEn);

    final photos = <StoryPhoto>[];
    for (final id in stop.photoIds) {
      final p = bundle.photoById(id);
      if (p != null) photos.add(p);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: scheme.primaryContainer),
              child: Text('${stop.seq}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name ?? tr('这一站'),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('${_hm(stop.arrive)} – ${_hm(stop.leave)}',
                      style:
                          TextStyle(fontSize: 11, color: scheme.outline)),
                ],
              ),
            ),
          ]),
          if (note != null) ...[
            const SizedBox(height: 10),
            Text(note, style: const TextStyle(fontSize: 14, height: 1.55)),
          ],
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PhotoGrid(bundle: bundle, photos: photos, stopName: name),
          ],
        ],
      ),
    );
  }
}

/// 照片网格。宽屏多排几列 —— 桌面端一行两张会蠢得很明显。
class _PhotoGrid extends StatelessWidget {
  final StoryBundle bundle;
  final List<StoryPhoto> photos;
  final String? stopName;
  const _PhotoGrid(
      {required this.bundle, required this.photos, this.stopName});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cols = (box.maxWidth / 180).floor().clamp(2, 6);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: photos.length,
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => StoryPhotoPage(
                bundle: bundle, photos: photos, index: i, title: stopName),
          )),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image(
              image: bundle.thumb(photos[i]),
              fit: BoxFit.cover,
              errorBuilder: (c, _, __) => ColoredBox(
                  color: Theme.of(c).colorScheme.surfaceContainerHighest),
            ),
          ),
        ),
      );
    });
  }
}

class _Summary extends StatelessWidget {
  final StoryBundle bundle;
  const _Summary({required this.bundle});

  @override
  Widget build(BuildContext context) {
    final s = bundle.story;
    final scheme = Theme.of(context).colorScheme;
    final dist = bundle.useMiles
        ? '${s.distanceMiles.round()} mi'
        : '${s.distanceKm.round()} km';

    Widget cell(String v, String label) => Column(children: [
          Text(v,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: scheme.outline)),
        ]);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        cell('${s.dayCount}', tr('天')),
        cell('${s.stopCount}', tr('站')),
        if (s.distanceMeters > 0) cell(dist, tr('里程')),
        cell('${s.photoCount}', tr('照片')),
      ]),
    );
  }
}

// ───────────────────────── 大图 ─────────────────────────

/// 全屏看图。左右翻、双指缩放；桌面端左右方向键翻、Esc 退出。
class StoryPhotoPage extends StatefulWidget {
  final StoryBundle bundle;
  final List<StoryPhoto> photos;
  final int index;
  final String? title;

  const StoryPhotoPage({
    super.key,
    required this.bundle,
    required this.photos,
    required this.index,
    this.title,
  });

  @override
  State<StoryPhotoPage> createState() => _StoryPhotoPageState();
}

class _StoryPhotoPageState extends State<StoryPhotoPage> {
  late final PageController _pager = PageController(initialPage: widget.index);
  late int _i = widget.index;
  final _focus = FocusNode();

  @override
  void dispose() {
    _pager.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = (_i + delta).clamp(0, widget.photos.length - 1);
    if (next != _i) {
      _pager.animateToPage(next,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      _go(1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.photos[_i].caption;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title == null
              ? '${_i + 1} / ${widget.photos.length}'
              : '${widget.title}  ·  ${_i + 1}/${widget.photos.length}',
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(children: [
          Expanded(
            child: PageView.builder(
              controller: _pager,
              onPageChanged: (i) => setState(() => _i = i),
              itemCount: widget.photos.length,
              itemBuilder: (_, i) => InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Image(
                    image: widget.bundle.full(widget.photos[i]),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined, color: Colors.white38),
                  ),
                ),
              ),
            ),
          ),
          if ((caption ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Text(caption!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
        ]),
      ),
    );
  }
}
