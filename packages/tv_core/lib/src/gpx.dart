import 'routing.dart';

/// GPX 1.1 读写。
///
/// **为什么要有 GPX，而 manifest 里却存 GeoJSON**:
///   - GeoJSON 是我们自己的规范格式: 紧凑、是 JSON、地图库直接吃，
///     存进 manifest 和 projects.json 用它
///   - GPX 是**互通格式**: Strava、Garmin、Google Earth、佳明手表、
///     几乎所有户外软件都认它。导出 GPX 意味着用户的路线不被我们锁住
///
/// 这和"照片是普通文件"是同一条原则: **数据要能带着走。**
class Gpx {
  static const _header = '<?xml version="1.0" encoding="UTF-8"?>';

  /// 把一条行程导出成 GPX。
  ///
  /// [stops] 写成航点（waypoint），[legs] 写成轨迹段（track segment）。
  /// 这样在别的软件里打开，既能看到路线，也能看到每一站叫什么。
  static String write({
    required String tripName,
    required List<GpxWaypoint> waypoints,
    required List<RouteLeg> legs,
  }) {
    final b = StringBuffer()
      ..writeln(_header)
      ..writeln('<gpx version="1.1" creator="TravelView" '
          'xmlns="http://www.topografix.com/GPX/1/1">')
      ..writeln('  <metadata><name>${_esc(tripName)}</name></metadata>');

    for (final w in waypoints) {
      b
        ..writeln('  <wpt lat="${w.point.lat}" lon="${w.point.lon}">')
        ..writeln('    <name>${_esc(w.name)}</name>');
      if (w.time != null) {
        b.writeln('    <time>${w.time!.toUtc().toIso8601String()}</time>');
      }
      b.writeln('  </wpt>');
    }

    if (legs.isNotEmpty) {
      b
        ..writeln('  <trk>')
        ..writeln('    <name>${_esc(tripName)}</name>');
      for (final leg in legs) {
        b.writeln('    <trkseg>');
        for (final p in leg.geometry) {
          b.writeln('      <trkpt lat="${p.lat}" lon="${p.lon}"></trkpt>');
        }
        b.writeln('    </trkseg>');
      }
      b.writeln('  </trk>');
    }

    b.writeln('</gpx>');
    return b.toString();
  }

  /// 读入 GPX 的轨迹点。
  ///
  /// 这条路径很有价值: 用户如果有行车记录仪、运动手表或 Strava 导出的轨迹，
  /// 导进来就能把路线的可信度从"推算"升级成 **actual —— 真实走过的路**。
  /// 这是任何在线路径规划都给不了的东西。
  static List<LatLon> readTrackPoints(String xml) {
    final out = <LatLon>[];
    final re = RegExp(
      r'<trkpt\s[^>]*?lat\s*=\s*"([-\d.]+)"[^>]*?lon\s*=\s*"([-\d.]+)"',
      caseSensitive: false,
    );
    for (final m in re.allMatches(xml)) {
      final lat = double.tryParse(m.group(1)!);
      final lon = double.tryParse(m.group(2)!);
      if (lat != null && lon != null) out.add(LatLon(lat, lon));
    }
    if (out.isEmpty) {
      // 有些导出工具把 lon 写在 lat 前面
      final re2 = RegExp(
        r'<trkpt\s[^>]*?lon\s*=\s*"([-\d.]+)"[^>]*?lat\s*=\s*"([-\d.]+)"',
        caseSensitive: false,
      );
      for (final m in re2.allMatches(xml)) {
        final lon = double.tryParse(m.group(1)!);
        final lat = double.tryParse(m.group(2)!);
        if (lat != null && lon != null) out.add(LatLon(lat, lon));
      }
    }
    return out;
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

class GpxWaypoint {
  final LatLon point;
  final String name;
  final DateTime? time;
  const GpxWaypoint({required this.point, required this.name, this.time});
}
