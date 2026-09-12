import 'dart:math';

/// 公开主页地址（handle）的规矩，和服务端 `web/src/app/api/handle/route.ts`
/// 里那条 zod 规则是**同一套**：小写字母、数字、下划线，3 到 20 位。
///
/// **为什么不让用户从空白开始输：** 一个空输入框加一句"小写字母、数字、
/// 下划线，3 到 20 位"，是把我们的数据库约束直接摊给用户看。
/// 他要在那儿现想一个名字、猜哪些字符能用、还可能撞名被打回来 ——
/// 而这一切发生在他只想赶紧把游记发出去的时候。
///
/// 正确的做法是**我们先给一个，他点一下确认**。想改的人永远可以改，
/// 但不想改的人（绝大多数）一次点击就走完了。
class HandleRules {
  HandleRules._();

  static const minLen = 3;
  static const maxLen = 20;

  static final _ok = RegExp(r'^[a-z0-9_]{3,20}$');

  static bool isValid(String h) => _ok.hasMatch(h);

  /// 从显示名或邮箱推一个地址出来。
  ///
  /// **中文名推不出东西，这是常态不是异常。** "李小明"清洗完是空字符串，
  /// 硬转拼音既不可靠又会推出他不认识的词。这种情况退回邮箱前缀，
  /// 再不行就发一个能读出来的随机词 —— 一个读得出来的 `wander_7f3a`，
  /// 比一串 uuid 好记得多，也比让用户卡在那儿强。
  static String suggest({String? name, String? email, Random? random}) {
    final rnd = random ?? Random();

    for (final raw in [name, email?.split('@').first]) {
      final s = _slug(raw);
      if (s.length >= minLen) return s.substring(0, min(s.length, maxLen));
    }
    return '${_words[rnd.nextInt(_words.length)]}_'
        '${rnd.nextInt(0x10000).toRadixString(16).padLeft(4, '0')}';
  }

  /// 撞名了换一个：在原来的基础上挂一个短后缀，而不是重新生成一个
  /// 完全不相干的词 —— 用户已经认下了那个名字，我们只是帮他绕开冲突。
  static String vary(String base, {Random? random}) {
    final rnd = random ?? Random();
    final suffix = rnd.nextInt(0x1000).toRadixString(16);
    final room = maxLen - suffix.length - 1;
    final head = base.length > room ? base.substring(0, room) : base;
    final out = '${head}_$suffix';
    return isValid(out) ? out : suggest(random: rnd);
  }

  static String _slug(String? raw) {
    if (raw == null) return '';
    final b = StringBuffer();
    for (final ch in raw.toLowerCase().runes) {
      final c = String.fromCharCode(ch);
      if (RegExp(r'[a-z0-9]').hasMatch(c)) {
        b.write(c);
      } else if (c == ' ' || c == '.' || c == '-' || c == '_') {
        // 连着的分隔符只留一个，结尾的不留
        if (b.isNotEmpty && !b.toString().endsWith('_')) b.write('_');
      }
      // 其它（中文、emoji、标点）直接丢掉
    }
    var s = b.toString();
    while (s.endsWith('_')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// 兜底用的词。都是**能读出来、拼得对、没有歧义**的旅行词 ——
  /// 用户要把这个地址念给别人听。
  static const _words = [
    'wander', 'roadside', 'compass', 'lantern', 'harbor', 'meadow',
    'skyline', 'driftwood', 'northbound', 'trailhead', 'sunbreak', 'atlas',
  ];
}
