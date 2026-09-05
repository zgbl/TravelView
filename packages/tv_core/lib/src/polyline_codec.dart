import 'routing.dart';

/// Encoded Polyline 编解码（Google 折线算法，支持 precision 5 和 6）。
///
/// **为什么要它**: 一条横穿美国的道路 geometry 有上万个点。
/// 存成 GeoJSON 数字数组大约每点 25-30 字节，编码后约 5-8 字节 ——
/// 差不多小四到五倍。manifest 体积直接决定分享页在手机上的打开速度，
/// 所以**服务端存编码串，渲染时再解回坐标**。
///
/// precision 6（polyline6）比 5 精确十倍（约 0.1 米），OSRM 默认用它。
/// 道路 geometry 用 6，避免在城市里出现折线抖动。
class PolylineCodec {
  static String encode(List<LatLon> points, {int precision = 6}) {
    final factor = _factor(precision);
    final sb = StringBuffer();
    var prevLat = 0, prevLon = 0;
    for (final p in points) {
      final lat = (p.lat * factor).round();
      final lon = (p.lon * factor).round();
      _encodeValue(lat - prevLat, sb);
      _encodeValue(lon - prevLon, sb);
      prevLat = lat;
      prevLon = lon;
    }
    return sb.toString();
  }

  static List<LatLon> decode(String encoded, {int precision = 6}) {
    final factor = _factor(precision);
    final out = <LatLon>[];
    var index = 0, lat = 0, lon = 0;
    while (index < encoded.length) {
      final dLat = _decodeValue(encoded, index);
      if (dLat == null) break;
      index = dLat.nextIndex;
      lat += dLat.value;

      final dLon = _decodeValue(encoded, index);
      if (dLon == null) break;
      index = dLon.nextIndex;
      lon += dLon.value;

      out.add(LatLon(lat / factor, lon / factor));
    }
    return out;
  }

  static int _factor(int precision) {
    var f = 1;
    for (var i = 0; i < precision; i++) {
      f *= 10;
    }
    return f;
  }

  static void _encodeValue(int value, StringBuffer sb) {
    var v = value < 0 ? ~(value << 1) : (value << 1);
    while (v >= 0x20) {
      sb.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    sb.writeCharCode(v + 63);
  }

  static _Decoded? _decodeValue(String s, int start) {
    var index = start;
    var shift = 0;
    var result = 0;
    int b;
    do {
      if (index >= s.length) return null;
      b = s.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final value = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    return _Decoded(value, index);
  }
}

class _Decoded {
  final int value;
  final int nextIndex;
  const _Decoded(this.value, this.nextIndex);
}
