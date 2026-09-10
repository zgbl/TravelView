import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

import '../state/account.dart';
import '../state/story_draft.dart';
import '../widgets/asset_thumb.dart';
import 'publish_page.dart';
import 'sign_in_page.dart';

/// 生成回顾：把选中的照片聚成一条**有站点的路线**，并且当场给用户看结果。
///
/// 这一步只在手机上算，不联网、不上传、不写文件 —— 用的是 `tv_core` 里
/// 和桌面端同一份聚类算法。用户点完按钮**必须立刻看到东西**：
/// 一个只弹提示条然后消失的按钮，比没有这个按钮更糟，
/// 因为它让人以为出了错。
class GeneratePage extends StatefulWidget {
  final List<PhotoRecord> photos;
  const GeneratePage(this.photos, {super.key});

  @override
  State<GeneratePage> createState() => _GeneratePageState();
}

class _GeneratePageState extends State<GeneratePage> {
  TripRoute? _route;
  String? _error;
  StoryDraft? _draft;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    // 让一帧先画出来，否则"正在生成"这一屏根本来不及显示
    await Future<void>.delayed(const Duration(milliseconds: 16));
    try {
      final r = buildRoute(widget.photos);
      if (!mounted) return;
      final start = r.stays.isEmpty
          ? widget.photos.first.takenAt
          : r.stays.first.arrive;
      setState(() {
        _route = r;
        _draft = StoryDraft(
            defaultTitle: '${start.year}.${start.month}.${start.day}');
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('回顾预览'))),
      body: _body(),
      bottomNavigationBar: _route == null ? null : _shareBar(),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(_error!, textAlign: TextAlign.center),
      ));
    }
    final route = _route;
    if (route == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
                width: 30, height: 30,
                child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(height: 16),
            Text(trf('正在把 {0} 张照片连成路线…', [widget.photos.length])),
          ],
        ),
      );
    }

    if (route.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            tr('选中的照片里没有带位置的，连不成路线。回上一页多选几张试试。'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final located = widget.photos.where((p) => p.hasLocation).toList();
    final draft = _draft!;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Cover(widget.photos.first,
            route: route, photoCount: widget.photos.length),
        _TitleFields(draft),
        _MapStrip(located),
        _TravelModePicker(draft),
        for (final stop in route.stays) _StopCard(stop, widget.photos, draft),
      ],
    );
  }

  Widget _shareBar() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: _publish,
              icon: const Icon(Icons.ios_share),
              label: Text(tr('发布并分享')),
            ),
          ),
        ),
      );

  /// 没登录就先登录，登录完**直接接着发** —— 不要把用户丢回上一屏
  /// 让他再点一次那个按钮，他刚才已经表达过意图了。
  Future<void> _publish() async {
    final settings = await AppSettings.load();
    final account = Account(settings);

    if (!account.signedIn) {
      if (!mounted) return;
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => SignInPage(account)),
      );
      if (ok != true) return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublishPage(
          photos: widget.photos,
          route: _route!,
          account: account,
          draft: _draft!,
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final PhotoRecord photo;
  final TripRoute route;
  final int photoCount;
  const _Cover(this.photo, {required this.route, required this.photoCount});

  @override
  Widget build(BuildContext context) {
    final km = route.totalKm.round();
    final start = route.stays.first.arrive;
    final end = route.stays.last.leave;
    final days = end.difference(start).inDays + 1;

    return Stack(
      children: [
        SizedBox(
            height: 260, width: double.infinity,
            child: AssetThumb(photo.id, size: 900)),
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
          ),
        ),
        Positioned(
          left: 18, right: 18, bottom: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${start.year}.${start.month}.${start.day}',
                style: const TextStyle(
                    color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  trf('{0} 天', [days]),
                  trf('{0} 站', [route.stays.length]),
                  if (km > 0) trf('{0} 公里', [km]),
                  trf('{0} 张', [photoCount]),
                ].join(' · '),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MapStrip extends StatelessWidget {
  final List<PhotoRecord> located;
  const _MapStrip(this.located);

  @override
  Widget build(BuildContext context) {
    if (located.length < 2) return const SizedBox.shrink();
    final pts = located.map((p) => LatLng(p.lat!, p.lon!)).toList();
    return SizedBox(
      height: 200,
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit:
              CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(30)),
          interactionOptions:
              const InteractionOptions(flags: InteractiveFlag.none),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.travelview.app',
          ),
          PolylineLayer(polylines: [
            Polyline(points: pts, strokeWidth: 3, color: const Color(0xFF2E6F6A)),
          ]),
        ],
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  final Stop stop;
  final List<PhotoRecord> all;
  final StoryDraft draft;
  const _StopCard(this.stop, this.all, this.draft);

  @override
  Widget build(BuildContext context) {
    final ids = stop.photoIds.toSet();
    final photos = all.where((p) => ids.contains(p.id)).toList();
    if (photos.isEmpty) return const SizedBox.shrink();

    final a = stop.arrive;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trf('第 {0} 站 · {1}月{2}日 {3}:{4}', [
              stop.seq,
              a.month,
              a.day,
              a.hour.toString().padLeft(2, '0'),
              a.minute.toString().padLeft(2, '0'),
            ]),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextFormField(
              initialValue: draft.stopNames[stop.seq],
              onChanged: (v) => draft.stopNames[stop.seq] = v,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                isDense: true,
                hintText: tr('这是哪儿？（可以不写）'),
                border: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextFormField(
              initialValue: draft.stopNotes[stop.seq],
              onChanged: (v) => draft.stopNotes[stop.seq] = v,
              textCapitalization: TextCapitalization.sentences,
              maxLines: null,
              decoration: InputDecoration(
                isDense: true,
                hintText: tr('这儿发生了什么'),
                border: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                    width: 96, child: AssetThumb(photos[i].id, size: 256)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 标题和副标题。**直接摆在封面下面，不藏进设置。**
///
/// 全都可以不写 —— 什么都不填也能发布，标题回落到日期。
/// 想发的时候被一个必填框拦住，比没有输入框更糟。
class _TitleFields extends StatelessWidget {
  final StoryDraft draft;
  const _TitleFields(this.draft);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: draft.title,
            onChanged: (v) => draft.title = v,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              isDense: true,
              hintText: trf('给这一篇起个名字（默认用 {0}）', [draft.defaultTitle]),
              border: InputBorder.none,
            ),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          TextFormField(
            initialValue: draft.subtitle,
            onChanged: (v) => draft.subtitle = v,
            textCapitalization: TextCapitalization.sentences,
            maxLines: null,
            decoration: InputDecoration(
              isDense: true,
              hintText: tr('一句话说说这趟（可以不写）'),
              border: InputBorder.none,
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// 路线上那个跟着走的标记长什么样。
///
/// **必须让用户选，不能猜。** 算法分不清"市内 30 公里"是开车还是坐地铁，
/// 在城里逛了一天却在路线上开一辆车跑，看的人第一眼就出戏。
/// 默认圆点 —— 不表态永远不会错。
class _TravelModePicker extends StatelessWidget {
  final StoryDraft draft;
  const _TravelModePicker(this.draft);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('路线上跟着走的标记'),
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: draft,
            builder: (context, _) => Wrap(
              spacing: 8,
              children: [
                for (final m in kTravelModes)
                  ChoiceChip(
                    selected: draft.travelMode == m.id,
                    onSelected: (_) => draft.setTravelMode(m.id),
                    label: Text('${m.emoji} ${tr(m.label)}'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
