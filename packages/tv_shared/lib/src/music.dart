import 'package:path/path.dart' as p;

import 'l10n.dart';

/// 配乐的规矩。
///
/// **手机端和桌面端是同一份判断，所以它住在这里。** 收什么格式、最多几首、
/// 什么算本地文件、界面上叫什么名字 —— 这些两端必须完全一致：
/// 桌面端收下了而手机端不收，用户会以为是手机坏了；反过来更糟，
/// 手机上装好的曲子发不出去。
///
/// 界面、落盘、导出各自不同，但"这一首到底收不收"只有一个答案。
class MusicRules {
  MusicRules._();

  /// 最多几首，轮流播放。
  ///
  /// 一趟长途行程配一首三分钟的曲子，循环七八遍会非常明显；
  /// 三首轮着放，同样的时长听感完全不同。
  static const maxTracks = 3;

  /// 收哪些后缀。**和 StoryExporter 的拷贝逻辑、服务器的音频白名单对得上** ——
  /// 这里放进来一种新格式，那两处也要一起放行，否则用户配了音乐却是哑的。
  static const audioExts = ['mp3', 'm4a', 'aac', 'ogg', 'wav'];

  /// 是不是随故事一起上传的本地文件（相对的另一个就是 https 外链）。
  static bool isLocal(String m) => !m.startsWith('https://');

  /// 一首曲子显示用的名字: 本地文件取文件名，外链取域名。
  static String label(String m) {
    if (m.startsWith('https://')) {
      return Uri.tryParse(m)?.host ?? tr('外部链接');
    }
    return p.basename(m);
  }

  /// 这首能不能收。只认两种东西: **https 直链**，和**本地文件的绝对路径**。
  ///
  /// 别的协议一律挡在外面。http 收进来是最坏的一种: 界面上它和正式曲子
  /// 长得一模一样，导出时 StoryExporter 会把它当成一个本地文件路径，
  /// 文件不存在就静默跳过 —— 用户要到发布之后才发现这一篇是哑的。
  static bool accepts(String v) {
    if (v.startsWith('https://')) return true;
    if (v.contains('://')) return false;
    return audioExts.contains(p.extension(v).replaceAll('.', '').toLowerCase());
  }
}
