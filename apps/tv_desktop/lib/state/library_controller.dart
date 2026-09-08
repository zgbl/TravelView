import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:tv_core/tv_core.dart';

import '../native/native_bridge.dart';
import 'app_settings.dart';
import 'projects.dart';
import '../export/story_exporter.dart';
import '../widgets/photo_tile.dart';

/// 桌面端的全部状态。业务逻辑一律在 tv_core 里，这里只负责调度和进度上报。
class LibraryController extends ChangeNotifier {
  Directory? _root;
  Catalog? _catalog;

  bool busy = false;
  String status = '';
  double? progress;
  List<LibraryIssue> issues = const [];
  String? lastError;

  ThumbnailCache? _thumbs;
  ThumbnailCache? get thumbs => _thumbs;

  /// 全局时间范围筛选。
  ///
  /// **筛选是"看"的方式，不是"存"的方式** —— 照片库永远只有一个、装全部照片，
  /// 想做哪段行程的报告就把范围调到哪段，照片视图和行程地图同时跟着变。
  /// 绝不需要为了做某次旅行的报告，把照片再导一份到新文件夹。
  DateTime? rangeStart;
  DateTime? rangeEnd;

  bool get hasRange => rangeStart != null || rangeEnd != null;

  /// 精确到分钟。做行程报告时同一天可能要切成上下午两段，
  /// 只能选到"天"是不够的。
  void setRange(DateTime? from, DateTime? to) {
    rangeStart = from;
    rangeEnd = to;
    _invalidate();
    _persist();
    notifyListeners();
  }

  /// 按整天设置（选日期时用），结束日包含当天 23:59:59
  void setDayRange(DateTime? from, DateTime? to) => setRange(
        from == null ? null : DateTime(from.year, from.month, from.day),
        to == null
            ? null
            : DateTime(to.year, to.month, to.day, 23, 59, 59),
      );

  void clearRange() => setRange(null, null);

  bool inRange(PhotoRecord r) {
    if (rangeStart != null && r.takenAt.isBefore(rangeStart!)) return false;
    if (rangeEnd != null && r.takenAt.isAfter(rangeEnd!)) return false;
    return true;
  }

  /// 当前范围内的照片。所有视图都用它，保证照片和地图看到的是同一批。
  List<PhotoRecord> get visiblePhotos {
    final all = _catalog?.photos ?? const <PhotoRecord>[];
    if (!hasRange) return all.toList();
    return all.where(inRange).toList();
  }

  int get visibleCount => visiblePhotos.length;

  /// 库里照片的时间跨度，用来给日期选择器一个合理的初始范围
  (DateTime, DateTime)? get libraryTimeSpan {
    final all = _catalog?.photos;
    if (all == null || all.isEmpty) return null;
    var min = all.first.takenAt, max = all.first.takenAt;
    for (final r in all) {
      if (r.takenAt.isBefore(min)) min = r.takenAt;
      if (r.takenAt.isAfter(max)) max = r.takenAt;
    }
    return (min, max);
  }

  /// 当前正在挑选的专辑名。选取只是打一个 tag，
  /// **不选取不等于删除** —— 照片一直在库里，只是没进这个专辑。
  String pickAlbum = '精选';

  ThumbnailWarmer? _warmer;
  int warmDone = 0;
  int warmTotal = 0;

  /// 后台预热进度。注意它**不占用** busy —— 预热期间所有操作照常可用。
  bool get warming => warmTotal > 0 && warmDone < warmTotal;

  /// 已经算出精选信号的照片数。没有信号 = 去重用不上，只能靠时间兜底。
  int get signalReadyCount =>
      _catalog?.photos.where((r) => r.phash != null).length ?? 0;

  Directory? get root => _root;
  Catalog? get catalog => _catalog;
  bool get hasLibrary => _catalog != null;
  int get photoCount => _catalog?.length ?? 0;

  int get gpsCount =>
      _catalog?.query(hasLocation: true).length ?? 0;

  int get totalBytes =>
      _catalog?.photos.fold<int>(0, (a, r) => a + r.bytes) ?? 0;

  List<MapEntry<String, List<PhotoRecord>>>? _byDayCache;

  /// 按日期倒序分组，最近的在最前面。
  /// **必须缓存**: 每次 build 都对几千张照片重新分组会明显拖慢界面。
  /// 库内容变化时调 _invalidate() 失效。
  List<MapEntry<String, List<PhotoRecord>>> get byDay {
    final cached = _byDayCache;
    if (cached != null) return cached;
    final map = <String, List<PhotoRecord>>{};
    for (final r in visiblePhotos) {
      map.putIfAbsent(LibraryLayout.dateStamp(r.takenAt), () => []).add(r);
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    for (final e in entries) {
      e.value.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    }
    _byDayCache = entries;
    return entries;
  }

  void _invalidate() => _byDayCache = null;

  File fileOf(PhotoRecord r) {
    final rel = _catalog!.relPathOf(r.id)!;
    return File(p.joinAll([_root!.path, ...p.posix.split(rel)]));
  }

  Tag get _pickTag => Tag('pick', pickAlbum);

  bool isPicked(PhotoRecord r) => r.tags.contains(_pickTag);

  int get pickedCount =>
      _catalog?.query(tagKind: 'pick', tagValue: pickAlbum).length ?? 0;

  /// 切换选取。写 sidecar 是真相，内存索引跟着更新。
  /// 返回切换后的状态，供 UI 立即反馈。
  Future<bool> togglePick(PhotoRecord r) async {
    final want = !isPicked(r);
    await setPicked(r, want);
    return want;
  }

  Future<void> setPicked(PhotoRecord r, bool on) async {
    final cat = _catalog;
    if (cat == null) return;
    final live = cat.byId(r.id) ?? r;
    if (isPicked(live) == on) return;
    await cat.setTag(r.id, _pickTag, on: on);
    // byDay 缓存里存的是旧的记录对象，不失效的话界面看不到选中状态
    _invalidate();
    notifyListeners();
  }

  /// 旋转照片 90 度，直接写回原文件。
  ///
  /// 只改 EXIF 方向标记，不重新编码，所以画质无损、拍摄时间不变。
  /// 但内容变了意味着**内容哈希变了**，id 会更新 —— 标签会完整保留。
  /// 返回新的 id（失败时返回 null）。
  Future<String?> rotate(PhotoRecord r, {bool clockwise = true}) async {
    final cat = _catalog;
    final th = _thumbs;
    if (cat == null || th == null) return null;
    final file = fileOf(r);

    final err = await NativeBridge.rotate(file.path, clockwise: clockwise);
    if (err != null) {
      lastError = err;
      notifyListeners();
      return null;
    }

    // 旋转后宽高互换，重新读一次元数据
    final meta = await NativeBridge.readMetadata(file.path);
    final updated = await cat.refreshAfterEdit(
      r.id,
      width: meta.width,
      height: meta.height,
    );
    if (updated == null) return null;

    // 旧的派生图作废
    for (final variant in ['thumbs', 'previews']) {
      final f = th.pathFor(r.id, variant: variant);
      if (await f.exists()) await f.delete();
    }
    _invalidate();
    notifyListeners();
    return updated.id;
  }

  /// 批量设置选取。给"自动精选"用 —— 一站几十张逐个写 sidecar 太慢，
  /// 这里按天合并，一个目录只写一次。
  Future<void> applyPicks({
    required Iterable<PhotoRecord> photos,
    required Set<String> pickedIds,
  }) async {
    final cat = _catalog;
    if (cat == null) return;
    for (final r in photos) {
      final want = pickedIds.contains(r.id);
      final live = cat.byId(r.id) ?? r;
      if (isPicked(live) == want) continue;
      await cat.setTag(r.id, _pickTag, on: want);
    }
    _invalidate();
    notifyListeners();
  }

  void setPickAlbum(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == pickAlbum) return;
    pickAlbum = trimmed;
    _persist();
    notifyListeners();
  }

  // ---- 道路路线 ----

  List<RouteLeg> roadLegs = const [];
  bool routing = false;
  int routeDone = 0;
  int routeTotal = 0;
  String? routeError;

  RouteCache? _routeCache;

  /// 路线模式: driving / walking / direct
  String get routeMode => settings.routeMode;

  set routeMode(String v) {
    if (settings.routeMode == v) return;
    settings.routeMode = v;
    roadLegs = const [];
    settings.save();
    notifyListeners();
  }

  RouteProvider _buildProvider() {
    switch (settings.routeProvider) {
      case 'osrm':
        return OsrmRouteProvider(baseUrl: settings.osrmBaseUrl);
      case 'direct':
        return const DirectRouteProvider();
      default:
        return OrsRouteProvider(apiKey: settings.orsApiKey);
    }
  }

  /// 导出/发布时用的路线。**Story 里绝不能没有线。**
  ///
  /// 地图是这个产品的核心画面，导出来只有几个孤零零的点是不能接受的。
  /// 所以这里保证覆盖当前行程的每一段:
  ///   1. 已经算过的道路路线直接用
  ///   2. 缺的（换过时间范围、改过聚类、还没点过"计算道路路线"）就现算
  ///   3. 还缺的用直线补上 —— 直线难看，但比断掉强，而且会如实标成 inferred
  Future<List<RouteLeg>> legsForStory(TripRoute trip) async {
    String key(String a, String b) => '$a>$b';
    final have = {for (final l in roadLegs) key(l.fromStopId, l.toStopId): l};
    final needed = [
      for (final l in trip.legs)
        (leg: l, k: key('stop-${l.from.seq}', 'stop-${l.to.seq}')),
    ];

    final missing = needed.where((n) => !have.containsKey(n.k)).toList();
    if (missing.isNotEmpty && settings.routeMode != 'direct' && !routing) {
      await computeRoads(trip);
      have
        ..clear()
        ..addEntries(
            roadLegs.map((l) => MapEntry(key(l.fromStopId, l.toStopId), l)));
    }

    // 直线兜底: 不进缓存 —— 缓存里只该有真实的道路数据
    final direct = RoutePlanner(provider: const DirectRouteProvider());
    final out = <RouteLeg>[];
    var fallback = 0;
    for (final n in needed) {
      var leg = have[n.k];
      // 缓存里可能存着几何为空的坏数据（早期版本、请求被截断），
      // 那会让地图上凭空少一段。宁可退回直线，也不能断线。
      if (leg == null || leg.geometry.length < 2) {
        leg = await direct.planLeg(n.leg);
        fallback++;
      }
      out.add(leg);
    }
    lastRouteSummary = fallback == 0
        ? '${out.length} 段全部是实际道路'
        : '${out.length} 段中有 $fallback 段没有道路数据，已用直线连上';
    return out;
  }

  /// 上一次导出时路线的实际情况，导出完成后显示给用户看
  String? lastRouteSummary;

  /// 算一次，永久存在照片库里。之后换模板、改范围、换电脑都不再请求网络。
  Future<void> computeRoads(TripRoute trip) async {
    if (_root == null || routing) return;
    if (settings.routeMode == 'direct') {
      roadLegs = const [];
      notifyListeners();
      return;
    }
    // 先做本地检查，避免明知会失败还打二十几次请求
    if (settings.routeProvider == 'ors' && settings.orsApiKey.trim().isEmpty) {
      routeError = '还没有填 openrouteservice 的 API key。'
          '点右边的齿轮填上，或改用自托管 OSRM / 只用直线。';
      notifyListeners();
      return;
    }

    routing = true;
    routeError = null;
    routeDone = 0;
    routeTotal = trip.legs.length;
    notifyListeners();

    try {
      _routeCache ??= RouteCache(
          File(p.join(_root!.path, LibraryLayout.catalogDir, 'routes.json')));
      await _routeCache!.load();

      final planner = RoutePlanner(
        provider: _buildProvider(),
        cache: _routeCache,
      );
      final mode = settings.routeMode == 'walking'
          ? TravelMode2.walking
          : TravelMode2.driving;

      roadLegs = await planner.planTrip(
        trip,
        mode: mode,
        onProgress: (d, t) {
          routeDone = d;
          routeTotal = t;
          notifyListeners();
        },
      );

      final fellBack = roadLegs
          .where((l) => l.provider == 'direct' && l.mode != TravelMode2.flight)
          .length;
      if (fellBack > 0) {
        // 把供应商返回的真实原因带出来，而不是让用户猜
        final why = planner.lastError;
        routeError = '$fellBack 段没能取到道路路线，已退回直线。'
            '${why == null ? '' : '原因: $why'}';
      }
    } catch (e) {
      routeError = '$e';
    } finally {
      routing = false;
      notifyListeners();
    }
  }

  // ---- 站点文字 / 地名 / AI ----

  NoteStore? _notes;
  Geocoder? _geo;
  bool aiBusy = false;
  String? aiError;

  NoteStore? get notes => _notes;
  Geocoder? get geocoder => _geo;

  StopNote? noteOf(Stop stop) => _notes?.get(stop);

  Future<void> saveNote(Stop stop, StopNote note) async {
    await _notes?.put(stop, note);
    notifyListeners();
  }

  PlaceInfo? placeOf(Stop stop) => _geo?.cached(stop.lat, stop.lon);

  /// 查这一站的地名和附近地标。每个站只查一次，结果永久缓存在照片库里。
  Future<PlaceInfo?> lookupPlace(Stop stop) async {
    final g = _geo;
    if (g == null) return null;
    final hit = g.cached(stop.lat, stop.lon);
    if (hit != null) return hit;
    final info = await g.lookup(stop.lat, stop.lon);
    notifyListeners();
    return info;
  }

  AiConfig get aiConfig => AiConfig(
        baseUrl: settings.aiBaseUrl,
        apiKey: settings.aiApiKey,
        model: settings.aiModel,
      );

  /// 组装这一站的提示词。**只有文字，没有照片。**
  StopFacts _factsOf(Stop stop, TripRoute trip) {
    final place = placeOf(stop);
    final idx = trip.stays.indexWhere((s) => s.seq == stop.seq);
    Leg? incoming;
    String? from;
    if (idx > 0) {
      incoming = trip.legs.firstWhere(
        (l) => l.to.seq == stop.seq,
        orElse: () => trip.legs.first,
      );
      final prev = trip.stays[idx - 1];
      from = placeOf(prev)?.primary ?? noteOf(prev)?.title;
    }
    // 这一段走了哪几条路: 从算好的道路路线里取。
    // 没算过真实路线（直线兜底）时就是空的，文案里自然也不会提路名
    final roads = idx > 0
        ? (roadLegs
                .where((l) => l.toStopId == 'stop-${stop.seq}')
                .map((l) => l.roads)
                .firstWhere((r) => r.isNotEmpty, orElse: () => const []))
        : const <String>[];

    return StopFacts.fromStop(
      stop,
      index: idx < 0 ? 0 : idx,
      total: trip.stays.length,
      placeNames: place?.names ?? const [],
      landmarks: place?.landmarks ?? const [],
      arrivedFrom: from,
      incomingLeg: idx > 0 ? incoming : null,
      viaRoads: roads,
    );
  }

  String buildPrompt(Stop stop, TripRoute trip, {String? userHint}) {
    return PromptBuilder.forStop(
      _factsOf(stop, trip),
      language: settings.aiLanguage,
      tone: settings.aiTone,
      tripTitle: currentProjectName,
      userHint: userHint,
    );
  }

  /// Level 1: **不用 AI 的事实型文案。**
  ///
  /// 只把已知信息写成一句话，不做任何推测，所以可以放心地批量自动填。
  /// [lookup] 为 true 时先查地名（会联网，且有 1 秒多的节流）。
  Future<FactCaption> factCaption(Stop stop, TripRoute trip,
      {bool lookup = true, String lang = 'zh'}) async {
    if (lookup) await lookupPlace(stop);
    return FactCaption.forStop(_factsOf(stop, trip),
        lang: lang, units: units);
  }

  /// 给还没有写过文字的站批量生成。**已经写过的一律不碰** ——
  /// 覆盖用户手写的内容是不可原谅的。
  Future<int> fillEmptyCaptions(TripRoute trip,
      {void Function(int done, int total)? onProgress}) async {
    var n = 0;
    final targets = trip.stays
        .where((s) => (noteOf(s)?.note.trim().isEmpty ?? true))
        .toList();
    for (var i = 0; i < targets.length; i++) {
      final stop = targets[i];
      // 中英各生成一份。事实型文案是拼出来的、不调模型，
      // 所以"顺手多生成一种语言"几乎不花任何代价
      final cap = await factCaption(stop, trip);
      final capEn = await factCaption(stop, trip, lookup: false, lang: 'en');
      final old = noteOf(stop);
      await saveNote(
        stop,
        StopNote(
          title: (old?.title.trim().isNotEmpty ?? false)
              ? old!.title
              : cap.title,
          note: cap.text,
          titleEn: capEn.title,
          noteEn: capEn.text,
          source: 'facts',
          updatedAt: DateTime.now(),
        ),
      );
      n++;
      onProgress?.call(i + 1, targets.length);
    }
    notifyListeners();
    return n;
  }

  /// 让用户自己的 AI 起草。生成的文字标记为 ai，用户改过就变成 aiEdited。
  Future<AiDraft?> draftNote(Stop stop, TripRoute trip,
      {String? userHint}) async {
    if (aiBusy) return null;
    aiBusy = true;
    aiError = null;
    notifyListeners();
    try {
      await lookupPlace(stop);
      final prompt = buildPrompt(stop, trip, userHint: userHint);
      final raw = await AiClient(aiConfig).complete(prompt);
      return AiDraft.parse(raw);
    } catch (e) {
      aiError = e is AiException ? e.toString() : '$e';
      return null;
    } finally {
      aiBusy = false;
      notifyListeners();
    }
  }

  // ---- 导出 Story ----

  bool exporting = false;
  int exportDone = 0;
  int exportTotal = 0;
  ExportResult? lastExport;

  /// 导出成一个可离线打开的 Story 网页包。
  /// **只导出被选中的照片的派生版本，原图一张都不复制。**
  Future<ExportResult?> exportStory({
    required TripRoute trip,
    required Map<int, String?> heroByStopSeq,
    String? coverPhotoId,
    String coverMode = 'map',
    String units = 'auto',
    required String title,
    String? subtitle,
    required TripRoute tripForNotes,
  }) async {
    final cat = _catalog;
    final root = _root;
    if (cat == null || root == null || exporting) return null;

    final selected = cat
        .query(tagKind: 'pick', tagValue: pickAlbum)
        .map((e) => e.id)
        .toSet();
    if (selected.isEmpty) {
      status = '还没有选中任何照片，先在「生成旅行回顾」里挑一些';
      notifyListeners();
      return null;
    }

    exporting = true;
    exportDone = 0;
    exportTotal = selected.length;
    status = '正在导出 Story...';
    lastError = null;
    notifyListeners();

    try {
      // 站点标题优先用用户写的，其次是反查到的地名
      final names = <int, String>{};
      final notesMap = <int, String>{};
      final namesEn = <int, String>{};
      final notesEn = <int, String>{};
      for (final stop in tripForNotes.stays) {
        final n = noteOf(stop);
        final place = placeOf(stop);
        final t = (n?.title.trim().isNotEmpty ?? false)
            ? n!.title.trim()
            : place?.primary;
        if (t != null && t.isNotEmpty) names[stop.seq] = t;
        if ((n?.note.trim().isNotEmpty ?? false)) {
          notesMap[stop.seq] = n!.note.trim();
        }
        // 英文版。**网页是双语的**，英文读者不该看到中文正文。
        // 没存过英文的（用户手写、AI 写的）就留空，前端回落到原文
        if ((n?.titleEn.trim().isNotEmpty ?? false)) {
          namesEn[stop.seq] = n!.titleEn.trim();
        }
        if ((n?.noteEn.trim().isNotEmpty ?? false)) {
          notesEn[stop.seq] = n!.noteEn.trim();
        }
      }

      // 先把路线补齐，绝不导出一张没有线的地图
      status = '正在准备路线...';
      notifyListeners();
      final legs = await legsForStory(trip);

      final exporter = StoryExporter(libraryRoot: root, catalog: cat);
      final res = await exporter.export(
        stopNames: names,
        stopNotes: notesMap,
        stopNamesEn: namesEn,
        stopNotesEn: notesEn,
        trip: trip,
        selectedIds: selected,
        heroByStopSeq: heroByStopSeq,
        coverPhotoId: coverPhotoId,
        coverMode: coverMode,
        units: units,
        legs: legs,
        title: title,
        subtitle: subtitle,
        onProgress: (d, t, label) {
          exportDone = d;
          exportTotal = t;
          status = '正在导出 $d/$t  $label';
          notifyListeners();
        },
      );
      lastExport = res;
      final mb = (res.totalBytes / 1024 / 1024).toStringAsFixed(1);
      status = '导出完成: ${res.photoCount} 张，共 $mb MB'
          '${lastRouteSummary == null ? '' : '，路线 $lastRouteSummary'}'
          '${res.warnings.isEmpty ? '' : '（${res.warnings.length} 个警告）'}';
      return res;
    } catch (e) {
      lastError = '$e';
      status = '导出失败';
      return null;
    } finally {
      exporting = false;
      notifyListeners();
    }
  }

  // ---- 发布到网站 ----

  bool publishing = false;
  int publishDone = 0;
  int publishTotal = 0;
  PublishResult? lastPublish;

  /// 额度不够时置为 true，UI 据此引导用户去网页付款，
  /// 而不是把 402 当成一个普通错误弹掉。
  bool needsPayment = false;

  /// 上次发布传到一半断了，这是那篇半成品的 id。
  /// **下次发布带上它就是接着传**: 已经传上去的图会被跳过，
  /// 也不会又建一篇、又扣一次额度。
  String resumeStoryId = '';
  String _resumeKey = '';

  /// 有没有一篇没传完的等着续传（而且就是当前这份产物）
  bool get canResume =>
      resumeStoryId.isNotEmpty &&
      _resumeKey.isNotEmpty &&
      _resumeKey == (lastExport?.storyKey ?? '');

  PublishConfig get publishConfig => PublishConfig(
        siteUrl: settings.siteUrl,
        token: settings.publishToken,
      );

  Future<void> savePublishSettings({
    required String siteUrl,
    required String token,
  }) async {
    settings.siteUrl = siteUrl.trim();
    settings.publishToken = token.trim();
    await settings.save();
    notifyListeners();
  }

  /// 把最近一次导出的目录发布出去。
  ///
  /// **必须先导出。** 发布上传的就是导出目录里那些已经剥掉 EXIF 的 WebP，
  /// 不会另找一条路去碰原图。
  Future<PublishResult?> publishStory({String visibility = 'public'}) async {
    final export = lastExport;
    if (export == null) {
      status = '先导出一次 Story，再发布';
      notifyListeners();
      return null;
    }
    if (publishing) return null;

    publishing = true;
    publishDone = 0;
    publishTotal = 0;
    needsPayment = false;
    lastError = null;
    status = '正在发布...';
    notifyListeners();

    try {
      // **只有用户明确勾了"更新那一篇"、而且内容确实是同一趟行程**，
      // 才带上 storyId。其余一切情况都是新发一篇。
      // 续传优先: 上次断在半路的那一篇就是这次要发的东西，
      // 接着传它，而不是留一篇残缺的在服务器上、这边再建一篇新的
      final existingId = canResume
          ? resumeStoryId
          // 用户自己挑的那一篇优先 —— 那是最明确的意图
          : (updateExisting && pickedStoryId.isNotEmpty)
              ? pickedStoryId
              : (updateExisting && canUpdatePublished)
                  ? (currentProject?.publishedStoryId ?? '')
                  : '';
      final res = await Publisher(publishConfig).publish(
        export.dir,
        visibility: visibility,
        storyId: existingId.isEmpty ? null : existingId,
        onCreated: (id) {
          // Story 一建好就记下来。**传图之前记** ——
          // 断在传图那一步时，这个 id 是能续传的唯一凭据
          resumeStoryId = id;
          _resumeKey = lastExport?.storyKey ?? '';
        },
        onProgress: (d, t, label) {
          publishDone = d;
          publishTotal = t;
          status = '正在发布 $d/$t 个文件  $label';
          notifyListeners();
        },
      );
      lastPublish = res;
      resumeStoryId = '';
      _resumeKey = '';
      // **发完之后仍然停在"更新这一篇"上。**
      // 更新是会反复做的事: 改完错别字发一次，换了封面再发一次。
      // 发完就把绑定清掉、按钮变回"发布新的一篇"，
      // 下一次手一快就多出一篇重复的。
      pickedStoryId = res.storyId;
      pickedStoryTitle = pickedStoryTitle.isNotEmpty
          ? pickedStoryTitle
          : (currentProjectName ?? '');
      pickedStoryUrl = res.publicUrl;
      updateExisting = true;
      await _rememberPublished(res);
      // 更新次数变了，把列表刷一下，好显示"还剩几次免费更新"
      unawaited(loadRemoteStories());
      status = res.updated
          ? '已更新: ${res.publicUrl}'
          : '发布成功: ${res.publicUrl}';
      return res;
    } on PublishException catch (e) {
      needsPayment = e.needsPayment;
      lastError = e.message;
      if ((e.storyId ?? '').isNotEmpty) {
        resumeStoryId = e.storyId!;
        _resumeKey = lastExport?.storyKey ?? '';
      }
      status = e.needsPayment
          ? '还没有可用的发布额度'
          : canResume
              ? '传到一半断了，再点一次「继续上传」接着传'
              : '发布失败';
      return null;
    } catch (e) {
      lastError = '$e';
      status = '发布失败';
      return null;
    } finally {
      publishing = false;
      notifyListeners();
    }
  }

  // ---- 片头封面 ----

  /// 用户选定的片头封面。**没选过就是空**，由 StoryBuilder 回落到自动挑的那张。
  /// 存在草稿里 —— 一个库里每趟行程各有各的封面。
  String get coverPhotoId => currentProject?.coverPhotoId ?? _tmpCover;
  String _tmpCover = '';

  /// 片头用什么。**默认整屏地图** ——
  /// 一张照片谁都有，这条真实走过的路线只有这一趟有。
  ///   auto    由内容决定: 有路线用地图，没有用照片（**默认**）
  ///   map     整屏真地图，标题压在下方的渐变里
  ///   mapcard 标题在地图外面，地图是一张干净的卡片
  ///   photo   一张照片
  ///
  /// 叫 Story Cover 而不是 Travel Map Cover: 这个产品以后不只有旅行，
  /// 生日 / 婚礼 / 演唱会都没有路线，封面引擎要能自己退回照片。
  String get coverMode => currentProject?.coverMode ?? _tmpCoverMode;
  String _tmpCoverMode = 'auto';

  static const coverModes = ['auto', 'map', 'mapcard', 'photo'];

  /// 距离单位。auto = 按行程所在国家（美/英用英里，其余公里）。
  /// **由用户决定，代码只在 auto 时才猜** —— 猜错一次，
  /// 整篇游记每一站的数字都是错的。
  String get units => currentProject?.units ?? _tmpUnits;
  String _tmpUnits = 'auto';

  static const unitOptions = ['auto', 'mi', 'km'];

  Future<void> setUnits(String u) async {
    _tmpUnits = unitOptions.contains(u) ? u : 'auto';
    final proj = currentProject;
    if (proj != null) {
      proj.units = _tmpUnits;
      proj.updatedAt = DateTime.now();
      await _store?.save(projects);
    }
    notifyListeners();
  }

  /// 封面上最大的那行字。空就用草稿名兜底。
  String get storyTitle =>
      currentProject?.storyTitle.isNotEmpty == true
          ? currentProject!.storyTitle
          : _tmpTitle;
  String _tmpTitle = '';

  String get storySubtitle =>
      currentProject?.storySubtitle.isNotEmpty == true
          ? currentProject!.storySubtitle
          : _tmpSubtitle;
  String _tmpSubtitle = '';

  Future<void> setStoryTitle(String title, {String? subtitle}) async {
    _tmpTitle = title.trim();
    if (subtitle != null) _tmpSubtitle = subtitle.trim();
    final proj = currentProject;
    if (proj != null) {
      proj.storyTitle = _tmpTitle;
      if (subtitle != null) proj.storySubtitle = _tmpSubtitle;
      proj.updatedAt = DateTime.now();
      await _store?.save(projects);
    }
    notifyListeners();
  }

  Future<void> setCoverMode(String mode) async {
    _tmpCoverMode = coverModes.contains(mode) ? mode : 'auto';
    final proj = currentProject;
    if (proj != null) {
      proj.coverMode = _tmpCoverMode;
      proj.updatedAt = DateTime.now();
      await _store?.save(projects);
    }
    notifyListeners();
  }

  Future<void> setCoverPhoto(String photoId) async {
    final proj = currentProject;
    // 还没保存过草稿时先记在内存里，保存时会一起写进去
    _tmpCover = photoId;
    if (proj != null) {
      proj.coverPhotoId = photoId;
      proj.updatedAt = DateTime.now();
      await _store?.save(projects);
    }
    notifyListeners();
  }

  /// 把服务器返回的 story id 记在当前草稿上。
  /// **记在草稿里而不是全局设置里** —— 一个照片库里有很多趟行程，
  /// 每一趟在网站上是各自独立的一篇。
  Future<void> _rememberPublished(PublishResult res) async {
    final proj = currentProject;
    if (proj == null || res.storyId.isEmpty) return;
    proj.publishedStoryId = res.storyId;
    proj.publishedUrl = res.publicUrl;
    // 指纹一起记下来。没有它，下次就没法判断"还是不是同一趟行程"
    proj.publishedKey = lastExport?.storyKey ?? '';
    proj.publishedTitle = currentProjectName ?? '';
    proj.updatedAt = DateTime.now();
    await _store?.save(projects);
  }

  /// 断开和网站上那一篇的关联，下次发布会新建一篇（并扣一次额度）。
  /// 用户在网站上把那篇删了、或者想另发一篇时用。
  Future<void> forgetPublished() async {
    final proj = currentProject;
    if (proj == null) return;
    proj.publishedStoryId = '';
    proj.publishedUrl = '';
    proj.publishedKey = '';
    proj.publishedTitle = '';
    updateExisting = false;
    await _store?.save(projects);
    notifyListeners();
  }

  // ---- 登录 ----

  bool loggingIn = false;
  String? loginError;

  bool get isLinked => settings.publishToken.trim().isNotEmpty;

  /// 邮箱 + 密码登录。**密码不落盘** ——
  /// 它只在这一次请求里出现，存下来的是服务器换回的令牌。
  Future<bool> login(String email, String password) async {
    if (loggingIn) return false;
    loggingIn = true;
    loginError = null;
    notifyListeners();
    try {
      final token = await DesktopLogin(settings.siteUrl)
          .signIn(email, password, label: Platform.localHostname);
      settings.publishToken = token;
      await settings.save();
      status = '已登录';
      return true;
    } on LoginException catch (e) {
      loginError = e.message;
      return false;
    } catch (e) {
      loginError = '$e';
      return false;
    } finally {
      loggingIn = false;
      notifyListeners();
    }
  }

  /// 只是把本机存的令牌删掉。**不吊销服务器上的令牌** ——
  /// 那要在网站的账户页做，这样"这台机器还能不能发布"始终由网站说了算。
  Future<void> logout() async {
    settings.publishToken = '';
    await settings.save();
    notifyListeners();
  }

  // ---- 工作进度（草稿）----

  List<Project> projects = [];
  String? currentProjectName;
  String clusterPreset = 'road';

  ProjectStore? get _store =>
      _root == null ? null : ProjectStore(_root!);

  Future<void> loadProjects() async {
    projects = await (_store?.load() ?? Future.value(<Project>[]));
    notifyListeners();
  }

  /// 把当前的时间范围、专辑、视图、聚类粒度存成一份命名草稿。
  /// 同名则覆盖。存在照片库里，换台电脑打开也在。
  Future<void> saveProject(String name, {String note = ''}) async {
    final store = _store;
    if (store == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    // 同名草稿是**覆盖**，不是新建 —— 已经发布过的那一篇的 id 必须留住，
    // 否则用户存一次盘，下次发布就变成了第二篇、还多扣一次额度
    final old = _projectNamed(trimmed);
    final proj = Project(
      name: trimmed,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      pickAlbum: pickAlbum,
      clusterPreset: clusterPreset,
      view: view,
      note: note,
      coverPhotoId: _tmpCover.isNotEmpty
          ? _tmpCover
          : (old?.coverPhotoId ?? ''),
      coverMode: _tmpCoverMode,
      storyTitle: _tmpTitle,
      storySubtitle: _tmpSubtitle,
      publishedStoryId: old?.publishedStoryId ?? '',
      publishedUrl: old?.publishedUrl ?? '',
    );
    projects.removeWhere((e) => e.name == trimmed);
    projects.insert(0, proj);
    await store.save(projects);
    currentProjectName = trimmed;
    status = '已保存工作进度「$trimmed」';
    _persist();
    notifyListeners();
  }

  /// 当前打开的那份草稿。发布状态挂在它身上。
  Project? get currentProject => _projectNamed(currentProjectName);

  Project? _projectNamed(String? name) {
    if (name == null) return null;
    for (final e in projects) {
      if (e.name == name) return e;
    }
    return null;
  }

  /**
   * 这次要发的**就是网站上那一篇**吗。
   *
   * 判定必须同时满足两条:
   *   1. 当前草稿记着一个 story id
   *   2. 这次导出的指纹和上次发布时**完全一致**
   *
   * 只看第一条是危险的: 用户在同一个草稿里换个时间范围，做的就是
   * 另一趟行程了，草稿名字却没变。这时候"更新"等于**把上一篇整个覆盖掉**，
   * 而上一篇的链接可能已经发给别人了。宁可让他多发一篇，
   * 也绝不能默默替换掉他发出去的东西。
   */
  bool get canUpdatePublished {
    final proj = currentProject;
    if (proj == null || proj.publishedStoryId.isEmpty) return false;
    final key = lastExport?.storyKey ?? '';
    if (key.isEmpty || proj.publishedKey.isEmpty) return false;
    if (proj.publishedKey == key) return true;
    // 日期变了一点也还算同一趟 —— 区间有重叠即可（见 updateCandidates）
    final now = key.split('|');
    final was = proj.publishedKey.split('|');
    if (now.length < 2 || was.length < 2) return false;
    return was[0].compareTo(now[1]) <= 0 && was[1].compareTo(now[0]) >= 0;
  }

  /// 草稿上挂着一篇已发布的，但**内容对不上**（换了行程）。
  /// UI 要据此明确告诉用户: 这次是新的一篇，不会动那一篇。
  bool get publishedIsDifferentTrip {
    final proj = currentProject;
    if (proj == null || proj.publishedStoryId.isEmpty) return false;
    return !canUpdatePublished;
  }

  String get publishedUrl => currentProject?.publishedUrl ?? '';
  String get publishedTitle => currentProject?.publishedTitle ?? '';

  /// 用户明确选择"更新那一篇"时才置 true。**默认永远是发新的一篇。**
  bool updateExisting = false;

  void setUpdateExisting(bool v) {
    updateExisting = v && (canUpdatePublished || pickedStoryId.isNotEmpty);
    notifyListeners();
  }

  // ---- 手动挑一篇来更新 ----
  //
  // 草稿里"上次发的是哪一篇"的记录会断: 换台电脑、重建草稿、
  // 或者内容改得指纹对不上。断了之后如果没有别的路，
  // 用户就永远更新不了自己的东西，只能重发一篇、旧链接烂在外面。

  List<RemoteStory> remoteStories = [];
  bool loadingStories = false;
  String pickedStoryId = '';
  String pickedStoryTitle = '';
  String pickedStoryUrl = '';

  /// 这次要发的日期范围（从导出产物的指纹里取）
  ({String start, String end})? get _exportRange {
    final k = lastExport?.storyKey ?? '';
    final parts = k.split('|');
    if (parts.length < 2 || parts[0].isEmpty) return null;
    return (start: parts[0], end: parts[1]);
  }

  /**
   * 可能是"同一趟行程"的已发布故事。
   *
   * 判定用**日期区间有重叠**，不用精确相等:
   * 用户完全可能多带一天、少带一天，或者删掉几张照片导致首尾日期变了 ——
   * 那还是同一趟旅行。要求精确相等，等于逼他重发一篇。
   *
   * 但重叠**只是候选**: 一律要用户自己确认要覆盖哪一篇，
   * 绝不自动选中。覆盖是不可撤销的，猜错的代价太大。
   */
  List<RemoteStory> get updateCandidates {
    final r = _exportRange;
    if (r == null) return const [];
    final out = remoteStories.where((s) {
      final a = s.start, b = s.end;
      if (a == null || b == null || a.isEmpty || b.isEmpty) return false;
      // 区间重叠: a <= 我的结束 且 b >= 我的开始
      return a.compareTo(r.end) <= 0 && b.compareTo(r.start) >= 0;
    }).toList();
    // 完全一致的排最前面，最可能就是它
    out.sort((x, y) {
      final xe = (x.start == r.start && x.end == r.end) ? 0 : 1;
      final ye = (y.start == r.start && y.end == r.end) ? 0 : 1;
      return xe.compareTo(ye);
    });
    return out;
  }

  Future<void> loadRemoteStories() async {
    if (loadingStories) return;
    loadingStories = true;
    lastError = null;
    notifyListeners();
    try {
      remoteStories = await Publisher(publishConfig).listStories();
    } on PublishException catch (e) {
      lastError = e.message;
    } catch (e) {
      lastError = '$e';
    } finally {
      loadingStories = false;
      notifyListeners();
    }
  }

  void pickStoryToUpdate(RemoteStory? s) {
    pickedStoryId = s?.id ?? '';
    pickedStoryTitle = s?.title ?? '';
    pickedStoryUrl = s?.url ?? '';
    updateExisting = pickedStoryId.isNotEmpty;
    notifyListeners();
  }

  Future<void> openProject(Project proj) async {
    // 换了草稿，"更新那一篇"的勾选必须清掉 —— 它属于上一个草稿
    updateExisting = false;
    _tmpCover = proj.coverPhotoId;
    _tmpTitle = proj.storyTitle;
    _tmpSubtitle = proj.storySubtitle;
    _tmpCoverMode = proj.coverMode;
    _tmpUnits = proj.units;
    rangeStart = proj.rangeStart;
    rangeEnd = proj.rangeEnd;
    pickAlbum = proj.pickAlbum;
    clusterPreset = proj.clusterPreset;
    view = proj.view;
    currentProjectName = proj.name;
    status = '已打开工作进度「${proj.name}」';
    _invalidate();
    _persist();
    notifyListeners();
  }

  Future<void> deleteProject(Project proj) async {
    final store = _store;
    if (store == null) return;
    projects.removeWhere((e) => e.name == proj.name);
    await store.save(projects);
    if (currentProjectName == proj.name) currentProjectName = null;
    notifyListeners();
  }

  void setClusterPreset(String v) {
    if (clusterPreset == v) return;
    clusterPreset = v;
    _persist();
    notifyListeners();
  }

  // ---- 跨启动保存工作状态 ----

  AppSettings settings = AppSettings();
  int view = 0;

  void setView(int v) {
    if (view == v) return;
    view = v;
    _persist();
    notifyListeners();
  }

  void _persist() {
    if (_restoring) return; // 恢复过程中不要回写，否则会覆盖掉待恢复的值
    settings
      ..lastLibraryPath = _root?.path
      ..rangeStart = rangeStart
      ..rangeEnd = rangeEnd
      ..view = view
      ..pickAlbum = pickAlbum
      ..clusterPreset = clusterPreset
      ..currentProject = currentProjectName;
    settings.save();
  }

  /// 启动时恢复上次的工作状态: 上次打开的库、时间范围、当前视图。
  bool _restoring = false;

  Future<void> restore() async {
    settings = await AppSettings.load();
    pickAlbum = settings.pickAlbum;
    view = settings.view;
    clusterPreset = settings.clusterPreset;
    currentProjectName = settings.currentProject;
    // 必须先把值取出来 —— openLibrary 内部会调 _persist()，
    // 那会用当前（还是空的）范围覆盖掉 settings，之前就是这样把自己覆盖没的
    final path = settings.lastLibraryPath;
    final savedStart = settings.rangeStart;
    final savedEnd = settings.rangeEnd;
    if (path == null || !await Directory(path).exists()) return;

    _restoring = true;
    try {
      await openLibrary(path, restoring: true);
      rangeStart = savedStart;
      rangeEnd = savedEnd;
      await loadProjects();
    } finally {
      _restoring = false;
    }
    _persist();
    _invalidate();
    notifyListeners();
  }

  Future<void> openLibrary(String path, {bool restoring = false}) async {
    await _guard('正在读取照片库...', () async {
      final dir = Directory(path);
      await Directory(p.join(dir.path, LibraryLayout.photosDir))
          .create(recursive: true);
      _warmer?.cancel();
      _root = dir;
      _catalog = Catalog(dir);
      _thumbs = ThumbnailCache(dir);
      _notes = NoteStore(dir);
      _geo = Geocoder(dir);
      await _notes!.load();
      await _geo!.load();
      final res = await _catalog!.rebuild();
      issues = res.issues;
      status = '已打开 ${res.photoCount} 张照片';
    });
    if (!restoring) {
      rangeStart = null;
      rangeEnd = null;
    }
    _persist();
    loadProjects();
    startWarming();
  }

  /// 后台把缩略图全部生成好，让浏览时不再有等待。
  /// 按界面显示顺序（最近的日期在前）预热，等待感最小。
  void startWarming() {
    final cat = _catalog, th = _thumbs;
    if (cat == null || th == null) return;
    _warmer?.cancel();
    final items = <MapEntry<String, File>>[];
    // 用全库而不是当前筛选范围 —— 信号是照片的固有属性，与在看哪一段无关
    final all = cat.photos.toList()
      ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    for (final r in all) {
      items.add(MapEntry(r.id, fileOf(r)));
    }
    if (items.isEmpty) return;
    warmDone = 0;
    warmTotal = items.length;
    _warmer = ThumbnailWarmer(
      cache: th,
      onProgress: (done, total) {
        warmDone = done;
        warmTotal = total;
        notifyListeners();
      },
      // 顺手把自动精选要用的信号补上（已导入的库靠这条回填）
      onThumbReady: (photoId, thumb) async {
        final rec = cat.byId(photoId);
        if (rec == null || rec.phash != null) return;
        final sig = await NativeBridge.analyze(thumb.path);
        if (sig == null) return;
        await cat.setSignals(
          photoId,
          sharpness: sig.sharpness,
          brightness: sig.brightness,
          phash: sig.phash,
          faceCount: sig.faceCount,
        );
      },
    );
    // 不 await —— 预热在后台跑，前台该干嘛干嘛
    _warmer!.run(items);
  }

  @override
  void dispose() {
    _warmer?.cancel();
    super.dispose();
  }

  /// 从一个文件夹导入。`tags` 用于给这批照片统一打标（例如"来自 iPhone 的这次旅行"）。
  Future<void> importFrom(String sourcePath, {List<Tag> tags = const []}) async {
    if (_catalog == null) return;
    await _guard('正在导入...', () async {
      final src = Directory(sourcePath);
      final files = <File>[];
      await for (final e in src.list(recursive: true, followLinks: false)) {
        if (e is File && !p.basename(e.path).startsWith('.')) files.add(e);
      }

      final importer = Importer(_catalog!);
      var imported = 0, dup = 0;
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        try {
          final meta = await NativeBridge.readMetadata(f.path);
          final stat = await f.stat();
          final r = await importer.importFile(
            f,
            // EXIF 拍摄时间才是真的；拿不到才退回文件修改时间
            takenAt: meta.takenAt ?? stat.modified,
            lat: meta.lat,
            lon: meta.lon,
            width: meta.width,
            height: meta.height,
            device: meta.device,
            tags: tags,
          );
          if (r.outcome == ImportOutcome.imported) {
            imported++;
          } else {
            dup++;
          }
        } catch (e) {
          lastError = '$e';
        }
        progress = (i + 1) / files.length;
        status = '正在导入 ${i + 1}/${files.length}';
        notifyListeners();
      }
      await _catalog!.writeJsonl();
      status = '导入完成: 新增 $imported 张，重复跳过 $dup 张';
      _invalidate();
      startWarming();
    });
  }

  /// 从 iPhone 直接导入。
  ///
  /// **手机上的照片全程只读**: 只调下载，从不删除、从不修改。
  /// 流程是「下载到临时目录 -> 导入照片库 -> 删掉临时副本」，
  /// 删的是 Mac 上的中转文件，不是手机上的照片。
  /// 从 iPhone 直接导入。
  ///
  /// **手机上的照片全程只读**: 只调下载，从不删除、从不修改。
  /// 流程是「下载到临时目录 -> 导入照片库 -> 删掉临时副本」，
  /// 删的是 Mac 上的中转文件，不是手机上的照片。
  ///
  /// [keys] 是 PhoneItem.key（文件夹路径+文件名），不能用裸文件名 ——
  /// iPhone 的 DCIM 分多个文件夹且文件名会绕回重复。
  /// [limitFrom]/[limitUntil] 是最后一道防线: 即使设备侧筛错了，
  /// 按 EXIF 拍摄时间再挡一次。传日期即可，内部按自然日取整。
  /// 这里刻意不用 DateTimeRange —— 那是 material 的类型，
  /// 状态层不该依赖 widget 库。
  Future<void> importFromPhone({
    required String deviceId,
    required List<String> keys,
    DateTime? limitFrom,
    DateTime? limitUntil,
    List<Tag> tags = const [],
  }) async {
    if (_catalog == null) return;
    await _guard('正在从手机读取...', () async {
      final staging = await Directory(
        p.join(Directory.systemTemp.path,
            'travelview_staging_${DateTime.now().millisecondsSinceEpoch}'),
      ).create(recursive: true);

      NativeBridge.setDownloadProgressHandler((done, total, name, error) {
        progress = total == 0 ? null : done / total;
        status = '正在从手机读取 $done/$total  $name';
        if (error != null) lastError = error;
        notifyListeners();
      });

      try {
        final files = await NativeBridge.downloadItems(
          deviceId: deviceId,
          keys: keys,
          destDir: staging.path,
        );

        status = '正在写入照片库...';
        notifyListeners();

        final from = limitFrom == null
            ? null
            : DateTime(limitFrom.year, limitFrom.month, limitFrom.day);
        final to = limitUntil == null
            ? null
            : DateTime(limitUntil.year, limitUntil.month, limitUntil.day)
                .add(const Duration(days: 1));

        final importer = Importer(_catalog!);
        var imported = 0, dup = 0, skipped = 0;
        for (var i = 0; i < files.length; i++) {
          final f = File(files[i].path);
          if (!await f.exists()) continue;
          final meta = await NativeBridge.readMetadata(f.path);
          final stat = await f.stat();
          final takenAt = meta.takenAt ?? stat.modified;

          // 兜底: 拍摄时间落在选定范围外的一律不入库
          if ((from != null && takenAt.isBefore(from)) ||
              (to != null && !takenAt.isBefore(to))) {
            skipped++;
            continue;
          }

          final r = await importer.importFile(
            f,
            takenAt: takenAt,
            lat: meta.lat,
            lon: meta.lon,
            width: meta.width,
            height: meta.height,
            device: meta.device,
            origFilename: files[i].origName,
            tags: tags,
          );
          if (r.outcome == ImportOutcome.imported) {
            imported++;
          } else {
            dup++;
          }
          progress = (i + 1) / files.length;
          status = '正在写入照片库 ${i + 1}/${files.length}';
          notifyListeners();
        }
        await _catalog!.writeJsonl();
        final res = await _catalog!.rebuild();
        issues = res.issues;
        status = skipped > 0
            ? '从手机导入完成: 新增 $imported 张，已有 $dup 张，'
                '$skipped 张不在所选日期范围内已跳过'
            : '从手机导入完成: 新增 $imported 张，已有 $dup 张';
        _invalidate();
        startWarming();
      } finally {
        NativeBridge.setDownloadProgressHandler(null);
        // 只清理 Mac 上的中转副本
        if (await staging.exists()) {
          await staging.delete(recursive: true);
        }
      }
    });
  }

  Future<void> rebuild() async {
    if (_catalog == null) return;
    await _guard('正在重建索引...', () async {
      final res = await _catalog!.rebuild();
      issues = res.issues;
      await _catalog!.writeJsonl();
      status = '重建完成: ${res.photoCount} 张照片，${res.issues.length} 个待处理项';
    });
  }

  Future<void> verify() async {
    if (_catalog == null) return;
    await _guard('正在校验...', () async {
      final report = await Verifier(_catalog!).run(onProgress: (d, t) {
        progress = t == 0 ? null : d / t;
        status = '正在校验 $d/$t';
        notifyListeners();
      });
      issues = report.problems;
      status = report.ok
          ? '校验通过: ${report.checked} 张照片全部完好'
          : '校验发现 ${report.problems.length} 个问题';
    });
  }

  Future<void> _guard(String label, Future<void> Function() body) async {
    _invalidate();
    busy = true;
    progress = null;
    lastError = null;
    status = label;
    notifyListeners();
    try {
      await body();
    } catch (e) {
      lastError = '$e';
      status = '出错了';
    } finally {
      _invalidate();
      busy = false;
      progress = null;
      notifyListeners();
    }
  }
}

String humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024.0;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}
