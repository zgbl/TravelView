import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'layout.dart';

/// 反查地名和附近地标的结果
class PlaceInfo {
  final List<String> names;      // 国家 / 州省 / 城市 / 街区
  final List<String> landmarks;  // 附近的地标，按距离排序
  final DateTime fetchedAt;

  const PlaceInfo({
    this.names = const [],
    this.landmarks = const [],
    required this.fetchedAt,
  });

  String? get primary => names.isEmpty ? null : names.last;

  Map<String, dynamic> toJson() => {
        'names': names,
        'landmarks': landmarks,
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  factory PlaceInfo.fromJson(Map<String, dynamic> j) => PlaceInfo(
        // 老缓存里可能存着没洗过的名字，读出来时再洗一遍
        names: ((j['names'] as List?)?.cast<String>() ?? const [])
            .map(Geocoder.cleanName)
            .where((e) => e.isNotEmpty)
            .toList(),
        landmarks: (j['landmarks'] as List?)?.cast<String>() ?? const [],
        fetchedAt: DateTime.tryParse(j['fetchedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// 地名与地标查询，基于 OpenStreetMap。
///
/// **每个站只查一次，结果永久缓存在照片库里。** 一趟旅行几十个站，
/// 也就几十次请求；之后换聚类参数、重做报告、换台电脑都不会再查。
///
/// 用的是 OSM 的公共服务，有明确的使用约束: 必须带 User-Agent、
/// 请求要限速。**量大了必须自托管**，这一点和地图瓦片是同一个道理。
class Geocoder {
  final Directory libraryRoot;
  final Map<String, PlaceInfo> _cache = {};
  DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  /// OSM 的使用政策要求每秒最多一次
  static const _minInterval = Duration(milliseconds: 1100);

  final String nominatimBase;
  final String overpassBase;
  final String language;

  Geocoder(
    this.libraryRoot, {
    this.nominatimBase = 'https://nominatim.openstreetmap.org',
    this.overpassBase = 'https://overpass-api.de/api/interpreter',
    this.language = 'zh,en',
  });

  File get file =>
      File(p.join(libraryRoot.path, LibraryLayout.catalogDir, 'places.json'));

  static String keyFor(double lat, double lon) =>
      '${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}';

  Future<void> load() async {
    _cache.clear();
    if (!await file.exists()) return;
    try {
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      j.forEach((k, v) {
        _cache[k] = PlaceInfo.fromJson(Map<String, dynamic>.from(v as Map));
      });
    } catch (_) {}
  }

  PlaceInfo? cached(double lat, double lon) => _cache[keyFor(lat, lon)];

  Future<PlaceInfo?> lookup(double lat, double lon,
      {bool withLandmarks = true}) async {
    final key = keyFor(lat, lon);
    final hit = _cache[key];
    if (hit != null) return hit;

    final names = await _reverse(lat, lon);
    final landmarks =
        withLandmarks ? await _nearbyLandmarks(lat, lon) : <String>[];
    if (names.isEmpty && landmarks.isEmpty) return null;

    final info = PlaceInfo(
      names: names,
      landmarks: landmarks,
      fetchedAt: DateTime.now(),
    );
    _cache[key] = info;
    await save();
    return info;
  }

  Future<List<String>> _reverse(double lat, double lon) async {
    final url = Uri.parse('$nominatimBase/reverse?format=jsonv2'
        '&lat=$lat&lon=$lon&zoom=14&addressdetails=1');
    final j = await _getJson(url);
    final addr = j?['address'];
    if (addr is! Map) return const [];

    // 从大到小取，重复的去掉
    const order = [
      'country', 'state', 'province', 'city', 'town', 'village',
      'suburb', 'neighbourhood', 'tourism', 'attraction',
    ];
    final out = <String>[];
    for (final k in order) {
      final v = addr[k];
      if (v is! String) continue;
      final name = cleanName(v);
      if (name.isEmpty || out.contains(name)) continue;
      out.add(name);
    }
    return out;
  }

  /// OSM 的名称字段并不干净: 常见 "美國俄亥俄州;Ohio" 这种多语言拼在一起，
  /// 也常见把上级行政区带进来。直接拿去写文案会出现
  /// "到美国;美國俄亥俄州"这种句子，所以入库前就洗一次。
  static String cleanName(String raw) {
    var s = raw.trim();
    // 多语言/别名分隔符，取第一个
    for (final sep in const [';', '；', ' / ', '|']) {
      final i = s.indexOf(sep);
      if (i > 0) s = s.substring(0, i).trim();
    }
    return s;
  }

  /// 附近 800 米内的地标。**只是"附近有什么"，不代表用户去过** ——
  /// 提示词里会明确交代这一点，避免 AI 编出"我参观了 XX"。
  Future<List<String>> _nearbyLandmarks(double lat, double lon) async {
    final q = '''
[out:json][timeout:20];
(
  node(around:800,$lat,$lon)["tourism"~"attraction|museum|viewpoint|artwork"];
  way(around:800,$lat,$lon)["tourism"~"attraction|museum|viewpoint"];
  node(around:800,$lat,$lon)["historic"];
  way(around:800,$lat,$lon)["historic"];
);
out center 20;
''';
    final j = await _postForm(Uri.parse(overpassBase), {'data': q});
    final els = j?['elements'];
    if (els is! List) return const [];

    final out = <String>[];
    for (final e in els) {
      final tags = e is Map ? e['tags'] : null;
      if (tags is! Map) continue;
      final name = (tags['name:zh'] ?? tags['name']) as String?;
      if (name != null && name.trim().isNotEmpty && !out.contains(name)) {
        out.add(name.trim());
      }
      if (out.length >= 6) break;
    }
    return out;
  }

  Future<void> _throttle() async {
    final since = DateTime.now().difference(_lastCall);
    if (since < _minInterval) {
      await Future<void>.delayed(_minInterval - since);
    }
    _lastCall = DateTime.now();
  }

  Future<Map<String, dynamic>?> _getJson(Uri url) async {
    await _throttle();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(url);
      // OSM 的使用政策要求可识别的 User-Agent
      req.headers.set('User-Agent', 'TravelView/0.1 (desktop app)');
      req.headers.set('Accept-Language', language);
      final resp = await req.close();
      if (resp.statusCode != 200) return null;
      final text = await resp.transform(utf8.decoder).join();
      final j = jsonDecode(text);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>?> _postForm(
      Uri url, Map<String, String> form) async {
    await _throttle();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final body = form.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final req = await client.postUrl(url);
      req.headers.set('User-Agent', 'TravelView/0.1 (desktop app)');
      req.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.write(body);
      final resp = await req.close();
      if (resp.statusCode != 200) return null;
      final text = await resp.transform(utf8.decoder).join();
      final j = jsonDecode(text);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ')
        .convert(_cache.map((k, v) => MapEntry(k, v.toJson()))));
    await tmp.rename(file.path);
  }
}
