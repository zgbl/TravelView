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

  static FactCaption forStop(StopFacts f) =>
      FactCaption(title: _title(f), text: _text(f));

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

  static String _text(StopFacts f) {
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
          : '，${_km(f.legMeters!)}';
      more.add('从${f.arrivedFrom!.trim()}${_verb(f.legMode)}过来$km。');
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

  static String _km(double meters) {
    final km = meters / 1000;
    if (km < 10) return '约 ${km.toStringAsFixed(1)} 公里';
    return '约 ${km.round()} 公里';
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
