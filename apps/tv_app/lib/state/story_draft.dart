import 'package:flutter/foundation.dart';
import 'package:tv_core/tv_core.dart';

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

  /// 站序号 -> 用户写的地名 / 一句话
  final Map<int, String> stopNames = {};
  final Map<int, String> stopNotes = {};

  /// 'drive' 开车 / 'walk' 逛城市 / 'dot' 只要圆点。
  ///
  /// **默认 dot，不替用户表态。** 算法分不清"市内 30 公里"是开车还是坐地铁，
  /// 猜错了路线上跑一辆车，看的人第一眼就出戏。
  String travelMode = 'dot';

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
