import 'dart:convert';
import 'dart:io';

import 'route.dart';
import 'routing.dart';

/// 路径规划失败的具体原因。
///
/// 只说"失败了"没用 —— 用户需要知道是没填 key、额度用尽、
/// 还是服务地址不通，才知道下一步该干什么。
class RouteProviderException implements Exception {
  final String provider;
  final String message;
  final int? statusCode;
  const RouteProviderException(this.provider, this.message, {this.statusCode});

  @override
  String toString() => statusCode == null
      ? '$provider: $message'
      : '$provider: HTTP $statusCode $message';
}

/// OSRM。自托管首选，也可指向任何兼容实例。
///
/// 数据来自 OpenStreetMap（ODbL）：**允许永久存储**，署名即可。
/// 这正是我们需要的 —— 路线要写进 manifest 并分发十年。
class OsrmRouteProvider implements RouteProvider {
  /// 例如 http://localhost:5000 或你自己部署的地址。
  /// 公共 demo 服务器只供试验，不可用于生产。
  final String baseUrl;
  final Duration timeout;

  const OsrmRouteProvider({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 20),
  });

  @override
  String get name => 'osrm';

  String _profile(TravelMode2 mode) =>
      mode == TravelMode2.walking ? 'foot' : 'driving';

  @override
  Future<RouteLeg?> route({
    required String fromStopId,
    required String toStopId,
    required LatLon from,
    required LatLon to,
    required TravelMode2 mode,
  }) async {
    final url = Uri.parse('$baseUrl/route/v1/${_profile(mode)}/'
        '${from.lon},${from.lat};${to.lon},${to.lat}'
        // steps=true 才有每一步的路名和路号（I 40 之类）
        '?overview=full&geometries=geojson&steps=true');
    final j = await _getJson(url, timeout: timeout, provider: name);

    final routes = j['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;
    final r = routes.first as Map<String, dynamic>;
    final coords = ((r['geometry'] as Map)['coordinates'] as List)
        .map((c) => LatLon.fromGeoJson(c as List))
        .toList();
    if (coords.length < 2) return null;

    return RouteLeg(
      fromStopId: fromStopId,
      toStopId: toStopId,
      mode: mode,
      source: RouteSource.inferred,
      provider: name,
      geometry: coords,
      distanceMeters: (r['distance'] as num?)?.toDouble() ?? 0,
      duration: r['duration'] == null
          ? null
          : Duration(seconds: (r['duration'] as num).round()),
      roads: _osrmRoads(r),
    );
  }

  /// OSRM 的每一步里，`ref` 是路号（I 40 / US 285），`name` 是路名。
  /// 优先要路号 —— 人说的是"走 40 号"，不是"走 Purple Heart Trail"。
  static List<String> _osrmRoads(Map<String, dynamic> r) {
    final by = <String, double>{};
    for (final leg in (r['legs'] as List? ?? const [])) {
      for (final st in ((leg as Map)['steps'] as List? ?? const [])) {
        final m = st as Map;
        final ref = (m['ref'] as String?)?.trim();
        final name = (m['name'] as String?)?.trim();
        final key = (ref != null && ref.isNotEmpty) ? ref : name;
        if (key == null || key.isEmpty) continue;
        by[key] = (by[key] ?? 0) + ((m['distance'] as num?)?.toDouble() ?? 0);
      }
    }
    return _topRoads(by);
  }
}

/// 按里程取前几条，太短的忽略 —— 出发前的两个路口不该出现在文案里
List<String> _topRoads(Map<String, double> byRoad, {int max = 3}) {
  final total = byRoad.values.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return const [];
  final kept = byRoad.entries
      .where((e) => e.value / total >= 0.12)   // 至少占这段路的 12%
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  // 路号里的分隔符不统一（I 40 / I-40 / I40），统一成 "I 40" 这种读法
  return kept
      .take(max)
      .map((e) => e.key.replaceAll(RegExp(r'[;/]'), ' / ').trim())
      .toList();
}

/// openrouteservice。托管服务，注册即有免费额度，起步最快。
/// 同样基于 OpenStreetMap，允许存储结果（需署名）。
class OrsRouteProvider implements RouteProvider {
  final String apiKey;
  final String baseUrl;
  final Duration timeout;

  const OrsRouteProvider({
    required this.apiKey,
    this.baseUrl = 'https://api.openrouteservice.org',
    this.timeout = const Duration(seconds: 25),
  });

  @override
  String get name => 'openrouteservice';

  String _profile(TravelMode2 mode) =>
      mode == TravelMode2.walking ? 'foot-walking' : 'driving-car';

  @override
  Future<RouteLeg?> route({
    required String fromStopId,
    required String toStopId,
    required LatLon from,
    required LatLon to,
    required TravelMode2 mode,
  }) async {
    final url =
        Uri.parse('$baseUrl/v2/directions/${_profile(mode)}/geojson');
    final body = jsonEncode({
      'coordinates': [from.toGeoJson(), to.toGeoJson()],
      // 要 steps 才有路名；ORS 默认就带 instructions，这里写明白
      'instructions': true,
    });
    if (apiKey.trim().isEmpty) {
      throw const RouteProviderException(
          'openrouteservice', '还没有填 API key（设置里填上即可）');
    }
    final j = await _postJson(url, body,
        headers: {'Authorization': apiKey}, timeout: timeout, provider: name);

    final features = j['features'] as List?;
    if (features == null || features.isEmpty) return null;
    final f = features.first as Map<String, dynamic>;
    final coords = ((f['geometry'] as Map)['coordinates'] as List)
        .map((c) => LatLon.fromGeoJson(c as List))
        .toList();
    if (coords.length < 2) return null;

    final summary =
        ((f['properties'] as Map?)?['summary'] as Map?) ?? const {};
    return RouteLeg(
      fromStopId: fromStopId,
      toStopId: toStopId,
      mode: mode,
      source: RouteSource.inferred,
      provider: name,
      geometry: coords,
      distanceMeters: (summary['distance'] as num?)?.toDouble() ?? 0,
      duration: summary['duration'] == null
          ? null
          : Duration(seconds: (summary['duration'] as num).round()),
      roads: _orsRoads(f),
    );
  }

  /// ORS 把每一步放在 properties.segments[].steps[]，路名在 `name`。
  /// 没有路名时它填 '-'，那种要丢掉。
  static List<String> _orsRoads(Map<String, dynamic> f) {
    final by = <String, double>{};
    final segs = (f['properties'] as Map?)?['segments'] as List? ?? const [];
    for (final seg in segs) {
      for (final st in ((seg as Map)['steps'] as List? ?? const [])) {
        final m = st as Map;
        final name = (m['name'] as String?)?.trim();
        if (name == null || name.isEmpty || name == '-') continue;
        by[name] = (by[name] ?? 0) + ((m['distance'] as num?)?.toDouble() ?? 0);
      }
    }
    return _topRoads(by);
  }
}

Future<Map<String, dynamic>> _getJson(Uri url,
    {required Duration timeout, required String provider}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.getUrl(url).timeout(timeout);
    req.headers.set('User-Agent', 'TravelView/0.1');
    final resp = await req.close().timeout(timeout);
    final text = await resp.transform(utf8.decoder).join().timeout(timeout);
    if (resp.statusCode != 200) {
      throw RouteProviderException(provider, _brief(text),
          statusCode: resp.statusCode);
    }
    return jsonDecode(text) as Map<String, dynamic>;
  } on RouteProviderException {
    rethrow;
  } catch (e) {
    throw RouteProviderException(provider, _reason(e));
  } finally {
    client.close(force: true);
  }
}

/// 把底层异常翻译成人话
String _reason(Object e) {
  final s = e.toString();
  if (e is SocketException) return '连不上服务（$s）';
  if (s.contains('TimeoutException')) return '请求超时';
  if (s.contains('HandshakeException')) return 'HTTPS 握手失败';
  return s;
}

String _brief(String body) {
  final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length > 160 ? '${t.substring(0, 160)}...' : t;
}

Future<Map<String, dynamic>> _postJson(Uri url, String body,
    {required Map<String, String> headers,
    required Duration timeout,
    required String provider}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.postUrl(url).timeout(timeout);
    req.headers.set('User-Agent', 'TravelView/0.1');
    req.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    headers.forEach(req.headers.set);
    req.write(body);
    final resp = await req.close().timeout(timeout);
    final text = await resp.transform(utf8.decoder).join().timeout(timeout);
    if (resp.statusCode != 200) {
      throw RouteProviderException(provider, _brief(text),
          statusCode: resp.statusCode);
    }
    return jsonDecode(text) as Map<String, dynamic>;
  } on RouteProviderException {
    rethrow;
  } catch (e) {
    throw RouteProviderException(provider, _reason(e));
  } finally {
    client.close(force: true);
  }
}

/// 路线缓存。**按端点坐标+模式做键，跨工作进度共用。**
///
/// 算一次就永久留在照片库里，之后换模板、改时间范围、换台电脑，
/// 都不会再打一次网络请求。这是"不依赖第三方"落到实处的地方。
class RouteCache {
  final File file;
  final Map<String, RouteLeg> _memo = {};

  RouteCache(this.file);

  static String keyFor(LatLon a, LatLon b, TravelMode2 mode) {
    String f(double v) => v.toStringAsFixed(4); // 约 10 米精度，足够定位一个站
    return '${f(a.lat)},${f(a.lon)}>${f(b.lat)},${f(b.lon)}|${mode.name}';
  }

  Future<void> load() async {
    _memo.clear();
    if (!await file.exists()) return;
    try {
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      j.forEach((k, v) {
        _memo[k] = RouteLeg.fromJson(Map<String, dynamic>.from(v as Map));
      });
    } catch (_) {
      // 缓存坏了不是致命问题，重算即可
    }
  }

  RouteLeg? get(LatLon a, LatLon b, TravelMode2 mode) =>
      _memo[keyFor(a, b, mode)];

  void put(LatLon a, LatLon b, TravelMode2 mode, RouteLeg leg) {
    _memo[keyFor(a, b, mode)] = leg;
  }

  int get length => _memo.length;

  Future<void> save() async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(
        _memo.map((k, v) => MapEntry(k, v.toJson()))));
    await tmp.rename(file.path);
  }
}

/// 把一条行程的所有段都规划出来。
///
/// 三条规则:
///   1. **飞行段永不贴合道路** —— 速度反推出来是飞行的，画直线（页面上是大圆弧虚线）
///   2. **失败一律退回直线** —— 行程图任何情况下都必须画得出来
///   3. **算完就抽稀再缓存** —— manifest 体积直接决定分享页在手机上的打开速度
class RoutePlanner {
  final RouteProvider provider;
  final RouteCache? cache;
  final double simplifyToleranceMeters;

  RoutePlanner({
    required this.provider,
    this.cache,
    this.simplifyToleranceMeters = 10,
  });

  /// 第一段失败的具体原因，供界面显示
  String? lastError;

  /// 连续失败到一定次数就不再打请求。
  /// 没填 key 的情况下没必要把 21 段全试一遍，每次都失败还慢。
  int _consecutiveFailures = 0;
  static const _giveUpAfter = 3;

  Future<List<RouteLeg>> planTrip(
    TripRoute trip, {
    TravelMode2 mode = TravelMode2.driving,
    void Function(int done, int total)? onProgress,
  }) async {
    final legs = <RouteLeg>[];
    final total = trip.legs.length;
    for (var i = 0; i < total; i++) {
      final leg = trip.legs[i];
      legs.add(await planLeg(leg, mode: mode));
      onProgress?.call(i + 1, total);
    }
    await cache?.save();
    return legs;
  }

  Future<RouteLeg> planLeg(Leg leg, {TravelMode2 mode = TravelMode2.driving}) async {
    // 用进出口而不是簇中心，避免在城市里连出一团毛线
    final from = LatLon(leg.from.routeExitLat, leg.from.routeExitLon);
    final to = LatLon(leg.to.routeEntryLat, leg.to.routeEntryLon);
    final fromId = 'stop-${leg.from.seq}';
    final toId = 'stop-${leg.to.seq}';

    // 飞行段不贴合道路
    if (leg.mode == TravelMode.fly) {
      return RouteLeg(
        fromStopId: fromId,
        toStopId: toId,
        mode: TravelMode2.flight,
        source: RouteSource.inferred,
        provider: 'direct',
        geometry: [from, to],
        distanceMeters: leg.meters,
      );
    }

    final cached = cache?.get(from, to, mode);
    if (cached != null) return cached;

    RouteLeg? result;
    if (_consecutiveFailures < _giveUpAfter) {
      try {
        result = await provider.route(
          fromStopId: fromId,
          toStopId: toId,
          from: from,
          to: to,
          mode: mode,
        );
        _consecutiveFailures = 0;
      } catch (e) {
        lastError ??= e is RouteProviderException ? e.toString() : '$e';
        _consecutiveFailures++;
        result = null;
      }
    }

    // 失败退回直线 —— 宁可画得朴素，也不能画不出来
    result ??= await const DirectRouteProvider().route(
      fromStopId: fromId,
      toStopId: toId,
      from: from,
      to: to,
      mode: mode,
    );

    final simplified = RouteLeg(
      fromStopId: result!.fromStopId,
      toStopId: result.toStopId,
      mode: result.mode,
      source: result.source,
      provider: result.provider,
      geometry: RoutePath.simplify(result.geometry,
          toleranceMeters: simplifyToleranceMeters),
      distanceMeters: result.distanceMeters,
      duration: result.duration,
    );
    if (simplified.provider != 'direct') {
      cache?.put(from, to, mode, simplified);
    }
    return simplified;
  }
}
