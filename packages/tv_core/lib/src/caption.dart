import 'prompt.dart';

/// Level 1: **不用 AI 的事实型文案。**
///
/// 只把已经知道的东西写成一句人话：什么时候到、待了多久、在哪、拍了多少张、
/// 从哪儿开过来的。**一个字都不推测**，所以永远不会出现"我们在这里吃了拉面"
/// 这种没发生过的事 —— 这也是它可以默认自动填、AI 却不行的原因。
///
/// 用户可以随便改，一改 source 就变成 factEdited，重新生成不会覆盖他写的东西。
class FactCaption {
  final String title;
  final String text;

  const FactCaption({required this.title, required this.text});

  /// [lang] 'zh' 中文 / 'en' English。
  ///
  /// **两种语言都要能生成。** 这段文字是事实的陈述，不是创作，
  /// 所以不需要调模型翻译 —— 同一批事实按目标语言的说法拼一遍就行，
  /// 又快又不会翻错地名。
  /// [units] 'auto' 按行程所在国家 / 'mi' 英里 / 'km' 公里。
  /// **中英文两版必须用同一个单位** —— 同一篇里中文说 78 公里、
  /// 英文说 48 miles，两个数都对，读者却对不上账。
  static FactCaption forStop(
    StopFacts f, {
    String lang = 'zh',
    String units = 'auto',
  }) {
    final miles = units == 'mi'
        ? true
        : units == 'km'
            ? false
            : f.usesMiles;
    return lang == 'en'
        ? FactCaption(title: _title(f), text: _textEn(f, miles))
        : FactCaption(title: _title(f), text: _text(f, miles));
  }

  // ---- 标题 ----

  static String _title(StopFacts f) {
    // 地名从小到大取第一个像"具体地点"的：街区 > 城市 > 州省 > 国家
    for (final n in f.placeNames.reversed) {
      final s = n.trim();
      if (s.isNotEmpty) return s;
    }
    return '第 ${f.index + 1} 站';
  }

  // ---- 正文 ----

  static String _text(StopFacts f, bool miles) {
    final parts = <String>[];

    final where = _where(f);
    final when = _when(f.arrive);
    parts.add(where == null ? '$when到达' : '$when到$where');

    final stay = _stay(f.duration);
    if (stay != null) parts.add(stay);

    // 说"共拍了"，因为页面上显示的是精选出来的张数，两个数字不一样，
    // 不写清楚就像是自相矛盾
    if (f.photoCount > 0) parts.add('共拍了 ${f.photoCount} 张照片');

    final first = '${parts.join('，')}。';

    final more = <String>[];
    if (f.arrivedFrom != null && f.arrivedFrom!.trim().isNotEmpty) {
      final km = f.legMeters == null || f.legMeters! < 500
          ? ''
          : '，${_dist(f.legMeters!, miles)}';
      // 走了哪条路是地图给的事实，而且**比里程具体得多** ——
      // "沿 40 号公路开了 136 公里"读起来才像一个真走过这条路的人
      final via = f.viaRoads.isEmpty
          ? ''
          : '，走${f.viaRoads.map(_roadZh).join('转')}';
      more.add('从${f.arrivedFrom!.trim()}${_verb(f.legMode)}过来$km$via。');
    }
    if (f.landmarks.isNotEmpty) {
      // 只列前三个，而且措辞是"一带有"，不是"参观了" —— 我们并不知道他去没去
      final list = f.landmarks.take(3).join('、');
      more.add('这一带有$list。');
    }

    return ([first] + more).join('');
  }

  static String? _where(StopFacts f) {
    final names = f.placeNames
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (names.isEmpty) return null;
    // 一句话里最多两级: 具体地点 + 上一级，太长反而不像人话
    final small = names.last;
    if (names.length == 1) return small;
    final big = names[names.length - 2];
    // "美国" + "美國俄亥俄州" 这种，下级名字里已经含着上级了，别再拼一遍。
    // 繁简写法不同也算，所以按去掉的字符数判断而不是简单 contains。
    if (small == big || small.contains(big) || big.contains(small)) {
      return small;
    }
    return '$big$small';
  }

  static String _when(DateTime t) {
    final h = t.hour;
    final slot = h < 5
        ? '凌晨'
        : h < 9
            ? '清晨'
            : h < 12
                ? '上午'
                : h < 14
                    ? '中午'
                    : h < 18
                        ? '下午'
                        : h < 22
                            ? '傍晚'
                            : '深夜';
    return '${t.month} 月 ${t.day} 日$slot';
  }

  /// 几分钟的停留不值得写 —— 那多半只是路过拍了张照。
  static String? _stay(Duration d) {
    final m = d.inMinutes;
    if (m < 20) return null;
    if (m < 60) return '停留约 $m 分钟';
    final h = d.inHours;
    if (h < 24) {
      final rest = m - h * 60;
      return rest < 15 ? '停留约 $h 小时' : '停留约 $h 个多小时';
    }
    return '待了约 ${(h / 24).round()} 天';
  }

  /// 距离。**单位由地点决定** —— 见 StopFacts.usesMiles
  static String _dist(double meters, bool miles) {
    final v = miles ? meters / 1609.344 : meters / 1000;
    final unit = miles ? '英里' : '公里';
    if (v < 10) return '约 ${v.toStringAsFixed(1)} $unit';
    return '约 ${v.round()} $unit';
  }

  /// 路号按中文习惯读: "I 40" -> "40 号州际公路"，"US 285" -> "285 号国道"。
  /// 认不出来的（普通街道名）原样保留 —— 硬翻只会翻错。
  static String _roadZh(String road) {
    final r = road.trim();
    final i = RegExp(r'^I[\s-]?(\d+)$', caseSensitive: false).firstMatch(r);
    if (i != null) return '${i.group(1)} 号州际公路';
    final us = RegExp(r'^US[\s-]?(\d+)$', caseSensitive: false).firstMatch(r);
    if (us != null) return '${us.group(1)} 号国道';
    final st = RegExp(r'^([A-Z]{2})[\s-]?(\d+)$').firstMatch(r);
    if (st != null) return '${st.group(1)} ${st.group(2)} 号公路';
    return r;
  }

  // ---- 英文版 ----
  //
  // 不是把中文逐句翻过去，而是**按英文的说法重写一遍同样的事实**。
  // 直译出来的句子（"On September 8 afternoon arrived at..."）
  // 一眼就能看出是机器翻的。

  static String _textEn(StopFacts f, bool miles) {
    final parts = <String>[];
    final where = _where(f);
    final when = _whenEn(f.arrive);
    parts.add(where == null ? 'Arrived $when' : 'Arrived at $where $when');

    final stay = _stayEn(f.duration);
    if (stay != null) parts.add(stay);
    if (f.photoCount > 0) {
      parts.add('took ${f.photoCount} '
          '${f.photoCount == 1 ? 'photo' : 'photos'} here');
    }
    final first = '${parts.join(', ')}.';

    final more = <String>[];
    if (f.arrivedFrom != null && f.arrivedFrom!.trim().isNotEmpty) {
      final km = f.legMeters == null || f.legMeters! < 500
          ? ''
          : ' ${_distEn(f.legMeters!, miles)}';
      final via = f.viaRoads.isEmpty
          ? ''
          : ' via ${f.viaRoads.join(' and ')}';
      more.add(' ${_verbEn(f.legMode)} from '
          '${f.arrivedFrom!.trim()}$km$via.');
    }
    if (f.landmarks.isNotEmpty) {
      more.add(' Nearby: ${f.landmarks.take(3).join(', ')}.');
    }
    return ([first] + more).join('');
  }

  static String _whenEn(DateTime t) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final h = t.hour;
    final slot = h < 5
        ? 'late at night'
        : h < 9
            ? 'early morning'
            : h < 12
                ? 'in the morning'
                : h < 14
                    ? 'around midday'
                    : h < 18
                        ? 'in the afternoon'
                        : h < 22
                            ? 'in the evening'
                            : 'late at night';
    return 'on ${months[t.month - 1]} ${t.day} $slot';
  }

  static String? _stayEn(Duration d) {
    final m = d.inMinutes;
    if (m < 20) return null;
    if (m < 60) return 'stayed about $m minutes';
    final h = d.inHours;
    if (h < 24) {
      final rest = m - h * 60;
      return rest < 15
          ? 'stayed about $h ${h == 1 ? 'hour' : 'hours'}'
          : 'stayed a bit over $h ${h == 1 ? 'hour' : 'hours'}';
    }
    final days = (h / 24).round();
    return 'stayed about $days ${days == 1 ? 'day' : 'days'}';
  }

  /// 同上: 一篇法国游记的英文版说 "48 miles" 和中文版说"78 公里"一样错
  static String _distEn(double meters, bool miles) {
    final v = miles ? meters / 1609.344 : meters / 1000;
    final unit = miles ? 'miles' : 'km';
    return v < 10
        ? '${v.toStringAsFixed(1)} $unit'
        : '${v.round()} $unit';
  }

  static String _verbEn(String? mode) {
    switch (mode) {
      case 'flight':
        return 'Flew';
      case 'walk':
        return 'Walked';
      case 'drive':
      default:
        return 'Drove';
    }
  }

  static String _verb(String? mode) {
    switch (mode) {
      case 'flight':
        return '飞';
      case 'walk':
        return '走';
      case 'drive':
      default:
        return '开';
    }
  }
}
