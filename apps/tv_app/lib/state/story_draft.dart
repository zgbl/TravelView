import 'package:flutter/foundation.dart';
import 'package:tv_shared/tv_shared.dart';

/// 用户为这一篇写的东西：标题、副标题、每一站的地名和一句话，
/// 以及路线上那个标记长什么样。
///
/// **文字是这个产品的一半。** 一串照片加一条线只是数据，
/// 让它变成"回顾"的是"第三天下午在这儿等了两个小时的雨"这种话。
/// 所以输入框不能藏在设置里，得摆在预览上，看到哪写到哪。
///
/// 全部可以留空 —— 什么都不写也能发布，标题回落到日期。
/// **不强迫用户写字**：想发的时候被一个必填框拦住，比没有输入框更糟。
class StoryDraft extends ChangeNotifier {
  StoryDraft({required this.defaultTitle});

  final String defaultTitle;

  String title = '';
  String subtitle = '';

  /// 站序号 -> 这一站的小标题 / 说明文字。
  ///
  /// **和桌面端同一个结构。** 桌面端按站组织，每一站是"照片在上、文字在下"，
  /// 手机端没有理由换一套 —— 同一个人在两个屏幕上做的是同一件事。
  final Map<int, String> stopNames = {};
  final Map<int, String> stopNotes = {};


  /// 这一篇分成几段（= 要写几段文字）。null 表示用自动估的那个数。
  ///
  /// **让用户自己定，因为只有他知道这趟有几件值得说的事。** 算法能看出
  /// 哪里停得久，看不出哪里"值得写"：同样是停 20 分钟，一个是加油，
  /// 一个是他等了半小时才等到的那片晚霞。
  ///
  /// **这个数只影响写字的段数，不影响地图。** 路线画的是合并之前的
  /// 全部地理点（见 tv_core 的 routePath）——自驾路上每一次停车拍照的
  /// 位置都在线上，小车照样一个点一个点地走过去，一个都不会少。
  int? chapterCount;

  void setChapterCount(int? n) {
    chapterCount = n;
    notifyListeners();
  }

  /// 片头封面那张照片的 id。**空表示不表态**，由 StoryBuilder 回落到
  /// 第一站的首图 —— 和桌面端同一条规则。
  ///
  /// 为什么值得单独存一个字段：这张是分享出去时别人第一眼看到的图，
  /// 也是社交平台抓的缩略图。让"第一站拍的第一张"来决定它，
  /// 等于让一张出发前在停车场随手拍的照片代表整趟旅行。
  String? coverId;

  /// 设为封面。**再点一次同一张就是取消** —— 用户设错了得有路回去，
  /// 而"取消封面"做成第二个菜单项会让菜单变长。
  void setCover(String? id) {
    coverId = (coverId == id) ? null : id;
    notifyListeners();
  }

  /// 这张照片被移出这一篇了 —— 它不能再当封面，否则导出时
  /// coverPhotoId 指向一张不在 Story 里的图。
  void dropCoverIfIs(String id) {
    if (coverId == id) {
      coverId = null;
      notifyListeners();
    }
  }

  /// 清空所有写过的字。**只清字，不动照片、配乐和封面** ——
  /// 用户点"清空文字"时脑子里想的就是那几段话。
  void clearText() {
    title = '';
    subtitle = '';
    stopNames.clear();
    stopNotes.clear();
    notifyListeners();
  }

  /// 'drive' 开车 / 'walk' 逛城市 / 'dot' 只要圆点。
  ///
  /// **默认 dot，不替用户表态。** 算法分不清"市内 30 公里"是开车还是坐地铁，
  /// 猜错了路线上跑一辆车，看的人第一眼就出戏。
  String travelMode = 'dot';

  /// 配乐，**最多三首，轮流播放**。每项是 MusicStore 里那份副本的绝对路径，
  /// 或 https:// 直链。
  ///
  /// 一趟长途行程配一首三分钟的曲子，循环七八遍会非常明显；
  /// 三首轮着放，同样的时长听感完全不同。
  ///
  /// **和桌面端同一个模型**（Project.music），导出时由同一份
  /// StoryExporter 处理：本地文件拷进 audio/ 跟着故事走，
  /// https 直链原样写进 manifest。
  final List<String> music = [];

  /// 用户声明拥有这些曲子的使用权。**每次增删都要重新声明** ——
  /// 一次勾选管到永远，等于没有声明。
  ///
  /// 发布时只有它为真才带上配乐（见 publish_page.dart）。曲子在上传那一刻
  /// 都会弹一次警告，用户按下"我确认"就等于这一次的声明，
  /// 所以正常情况下它是勾上的；留这个开关是让他能随手撤回。
  bool musicRightsOk = false;

  /// 配乐的规矩（最多几首、收什么格式、什么算本地文件、显示成什么名字）
  /// **住在 tv_shared 的 [MusicRules] 里**，桌面端用的是同一份。
  /// 这里只留一层转手，不再各写各的 —— 手机上装好的曲子发不出去，
  /// 比什么都伤人。
  static const maxTracks = MusicRules.maxTracks;
  static const audioExts = MusicRules.audioExts;

  static bool isLocalTrack(String m) => MusicRules.isLocal(m);
  static String trackLabel(String m) => MusicRules.label(m);
  static bool accepts(String v) => MusicRules.accepts(v);

  /// 加一首。重复的、超过三首的、格式不对的，一律忽略（返回 false）。
  /// **加完之后版权声明要重来** —— 新曲子没被声明过。
  bool addMusic(String m) {
    final v = m.trim();
    if (v.isEmpty) return false;
    if (!accepts(v)) return false;
    if (music.contains(v) || music.length >= maxTracks) return false;
    music.add(v);
    musicRightsOk = false;
    notifyListeners();
    return true;
  }

  void removeMusic(String m) {
    music.remove(m);
    if (music.isEmpty) musicRightsOk = false;
    notifyListeners();
  }

  /// 只改版权声明，不动曲目。没有曲子时它只能是假 ——
  /// 一个"对空集合的声明"会一直亮着，下次加曲子时看起来像是已经声明过了。
  void setMusicRights(bool ok) {
    musicRightsOk = music.isEmpty ? false : ok;
    notifyListeners();
  }

  /// 发布时真正要带上的配乐。**没声明就一首都不带** ——
  /// 声明是这条路成立的前提，不是走过场。
  List<String> get musicForPublish => musicRightsOk ? music : const [];

  String get effectiveTitle =>
      title.trim().isEmpty ? defaultTitle : title.trim();

  void setTravelMode(String m) {
    travelMode = m;
    notifyListeners();
  }

  Map<int, String> get names => {
        for (final e in stopNames.entries)
          if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
      };

  Map<int, String> get notes => {
        for (final e in stopNotes.entries)
          if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
      };

  /// 有没有写过东西。用来决定退出时要不要提醒。
  bool get hasText =>
      title.trim().isNotEmpty ||
      subtitle.trim().isNotEmpty ||
      names.isNotEmpty ||
      notes.isNotEmpty;
}

/// 路线标记的三个选项。文案是给用户看的，不是给程序员看的 ——
/// 写 'drive' / 'walk' 用户不知道那是什么。
const kTravelModes = <({String id, String label, String emoji})>[
  (id: 'dot', label: '只要圆点', emoji: '⚪'),
  (id: 'walk', label: '逛城市', emoji: '🚶'),
  (id: 'drive', label: '开车', emoji: '🚗'),
];
