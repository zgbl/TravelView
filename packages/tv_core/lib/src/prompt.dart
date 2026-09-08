import 'models.dart';
import 'route.dart';

/// 一站已知的客观事实。全部来自照片本身和地图数据，没有任何推测。
class StopFacts {
  final int index;
  final int total;
  final DateTime arrive;
  final DateTime leave;
  final int photoCount;
  final double lat;
  final double lon;

  /// 反查到的地名，从大到小: 国家 / 州省 / 城市 / 街区
  final List<String> placeNames;

  /// 附近的地标，按距离排序
  final List<String> landmarks;

  /// 上一站到这一站的信息
  final String? arrivedFrom;
  final double? legMeters;
  final String? legMode;

  /// 这一段主要走了哪几条路（'I 40' 之类）。
  /// "沿 40 号州际公路开过来"比"开了 136 公里"具体得多，
  /// 而且这是**地图给的事实**，不是编的。
  final List<String> viaRoads;

  const StopFacts({
    required this.index,
    required this.total,
    required this.arrive,
    required this.leave,
    required this.photoCount,
    required this.lat,
    required this.lon,
    this.placeNames = const [],
    this.landmarks = const [],
    this.arrivedFrom,
    this.legMeters,
    this.legMode,
    this.viaRoads = const [],
  });

  Duration get duration => leave.difference(arrive);

  /**
   * 这一站该用英里还是公里。
   *
   * **单位跟地点走，不跟语言走。** 一趟美国自驾，中文读者看到"78 公里"
   * 一样别扭 —— 路牌上写的是 mile，开车时看的里程表也是 mile。
   * 反过来，一篇法国游记的英文版说 "48 miles" 同样不对。
   *
   * 判断优先用反查到的国名；地名没查到时用经纬度兜底，
   * 因为**没有地名的那一站恰恰最常见于荒郊野外的公路上**，
   * 而那正是最需要说对单位的场合。
   */
  bool get usesMiles {
    for (final n in placeNames) {
      final s = n.trim().toLowerCase();
      if (s.isEmpty) continue;
      if (_mileCountries.any(s.contains)) return true;
      // 明确是别的国家就不用再猜了
      if (_metricHints.any(s.contains)) return false;
    }
    return _inUsBox(lat, lon);
  }

  /// 日常路程仍用英里的地方: 美国、英国、利比里亚、缅甸
  static const _mileCountries = [
    'united states', 'usa', 'u.s.', 'america', '美国', '美國',
    'united kingdom', 'england', 'scotland', 'wales',
    'northern ireland', 'britain', '英国', '英國',
    'liberia', '利比里亚', 'myanmar', 'burma', '缅甸', '緬甸',
  ];

  /// 出现这些就肯定不是英里国家，避免"United States"匹配到别的词
  static const _metricHints = [
    'canada', '加拿大', 'mexico', '墨西哥', 'china', '中国', '中國',
    'japan', '日本', 'france', '法国', 'germany', '德国', 'australia',
  ];

  /// 美国本土 + 阿拉斯加 + 夏威夷的粗略范围。
  /// 只在地名查不到时用，宁可粗一点也别把加拿大算进来
  static bool _inUsBox(double lat, double lon) {
    final mainland =
        lat >= 24.5 && lat <= 49.0 && lon >= -125.0 && lon <= -66.9;
    final alaska = lat >= 51.0 && lat <= 71.5 && lon >= -170.0 && lon <= -129.0;
    final hawaii = lat >= 18.5 && lat <= 22.5 && lon >= -160.5 && lon <= -154.5;
    return mainland || alaska || hawaii;
  }

  static StopFacts fromStop(
    Stop stop, {
    required int index,
    required int total,
    List<String> placeNames = const [],
    List<String> landmarks = const [],
    String? arrivedFrom,
    Leg? incomingLeg,
    List<String> viaRoads = const [],
  }) =>
      StopFacts(
        index: index,
        total: total,
        arrive: stop.arrive,
        leave: stop.leave,
        photoCount: stop.photoCount,
        lat: stop.lat,
        lon: stop.lon,
        placeNames: placeNames,
        landmarks: landmarks,
        arrivedFrom: arrivedFrom,
        legMeters: incomingLeg?.meters,
        legMode: incomingLeg?.mode.name,
        viaRoads: viaRoads,
      );
}

/// 生成给 AI 的提示词。
///
/// 三条原则:
///   1. **只给事实，不给推测** —— 提示词里的每一条都来自照片元数据或地图数据
///   2. **明确禁止编造** —— 旅行文案一旦编出"我们在祇园吃了拉面"这种没发生过的事，
///      用户对整个产品的信任就崩了
///   3. **提示词本身要能给用户看** —— 他要知道我们把什么信息发出去了
class PromptBuilder {
  /// [language] 例如 '中文' / 'English'
  /// [tone] 例如 '简洁克制' / '生动一些'
  static String forStop(
    StopFacts f, {
    String language = '中文',
    String tone = '简洁克制',
    int maxWords = 60,
    String? tripTitle,
    String? userHint,
  }) {
    final b = StringBuffer();
    b.writeln('你在帮我给一次旅行的某一站写一小段说明文字。');
    b.writeln();
    b.writeln('## 已知事实（只能用这些，不要编造任何未列出的内容）');
    if (tripTitle != null && tripTitle.trim().isNotEmpty) {
      b.writeln('- 这次旅行: $tripTitle');
    }
    b.writeln('- 这是第 ${f.index + 1} 站，共 ${f.total} 站');
    b.writeln('- 到达: ${_dt(f.arrive)}');
    b.writeln('- 离开: ${_dt(f.leave)}');
    b.writeln('- 停留时长: ${_dur(f.duration)}');
    b.writeln('- 在这里拍了 ${f.photoCount} 张照片');
    if (f.placeNames.isNotEmpty) {
      b.writeln('- 位置: ${f.placeNames.join(' / ')}');
    } else {
      b.writeln('- 坐标: ${f.lat.toStringAsFixed(4)}, '
          '${f.lon.toStringAsFixed(4)}（没有查到地名）');
    }
    if (f.landmarks.isNotEmpty) {
      b.writeln('- 附近的地标: ${f.landmarks.join('、')}');
      b.writeln('  （这只是附近有什么，**不代表我去过**，'
          '不确定就不要说我参观了它）');
    }
    if (f.arrivedFrom != null) {
      final km = f.legMeters == null
          ? ''
          : '，约 ${(f.legMeters! / 1000).round()} 公里';
      b.writeln('- 从「${f.arrivedFrom}」过来$km');
    }
    if (f.viaRoads.isNotEmpty) {
      b.writeln('- 这段路主要走的是: ${f.viaRoads.join('、')}'
          '（地图给的路名/路号，可以直接写进文字里）');
    }
    if (userHint != null && userHint.trim().isNotEmpty) {
      b.writeln();
      b.writeln('## 我补充的信息');
      b.writeln(userHint.trim());
    }

    b.writeln();
    b.writeln('## 要求');
    b.writeln('- 用$language写');
    b.writeln('- 语气$tone，像旅行笔记，不要像导游词或百科词条');
    b.writeln('- 不超过 $maxWords 字');
    b.writeln('- **绝对不要编造上面没有的事实**：'
        '没写吃了什么就不要写吃的，没写天气就不要写天气，'
        '没写和谁一起就不要写同伴');
    b.writeln('- 不要用"仿佛""令人流连忘返"这类空洞的修辞');
    b.writeln('- 直接输出正文，不要标题、不要解释、不要引号');
    b.writeln();
    b.writeln('另外单独给我一个不超过 8 个字的小标题，'
        '写在正文前面，用一行 "标题: xxx" 的格式。');
    return b.toString();
  }

  static String _dt(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  static String _dur(Duration d) {
    if (d.inMinutes < 1) return '很短';
    if (d.inMinutes < 60) return '${d.inMinutes} 分钟';
    if (d.inHours < 24) {
      final m = d.inMinutes % 60;
      return m == 0 ? '${d.inHours} 小时' : '${d.inHours} 小时 $m 分钟';
    }
    return '${d.inDays} 天';
  }
}

/// 从 AI 返回的文本里拆出标题和正文
class AiDraft {
  final String title;
  final String note;
  const AiDraft(this.title, this.note);

  factory AiDraft.parse(String raw) {
    final lines = raw.trim().split('\n');
    var title = '';
    final body = <String>[];
    for (final line in lines) {
      final t = line.trim();
      if (title.isEmpty) {
        final m = RegExp(r'^(标题|title)\s*[:：]\s*(.+)$', caseSensitive: false)
            .firstMatch(t);
        if (m != null) {
          title = m.group(2)!.trim();
          continue;
        }
      }
      if (t.isNotEmpty) body.add(t);
    }
    return AiDraft(title, body.join('\n'));
  }
}
