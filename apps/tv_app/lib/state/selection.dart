import 'package:flutter/foundation.dart';
import 'package:tv_core/tv_core.dart';

/// 一趟行程里"要放进回顾的照片"。
///
/// **默认全选。**
///
/// 这不是随便定的：用户点进一趟行程，想的是"把这次旅行发出去"，
/// 不是"从三百张里挑三十张"。默认全不选的话，他要先干三分钟体力活
/// 才能看到第一个结果 —— 而这三分钟里他还不知道结果长什么样，
/// 凭什么判断该留哪张？
///
/// 所以挑图在这里是**减法**：先全要，看着不顺眼的划掉。
/// 等阶段 2 接上 `Curator`，默认值换成"自动精选出来的那批"，
/// 交互一个字都不用改 —— 用户照样是在一个已经成形的结果上做增删。
class TripSelection extends ChangeNotifier {
  TripSelection(List<PhotoRecord> photos)
      : _all = photos,
        _picked = {
          // 截图默认不要。它们混在旅行照片里几乎总是噪音，
          // 但**不是删掉**：用户想要还能自己勾回来。
          for (final p in photos)
            if (!p.isScreenshot) p.id,
        };

  final List<PhotoRecord> _all;
  final Set<String> _picked;

  /// 是否处在多选状态。平时点照片是看大图，进了多选才是勾选。
  bool _selecting = false;
  bool get selecting => _selecting;

  int get total => _all.length;
  int get count => _picked.length;
  bool get isEmpty => _picked.isEmpty;

  bool has(String id) => _picked.contains(id);

  /// 按原本的时间顺序返回选中的照片。
  List<PhotoRecord> get picked =>
      _all.where((p) => _picked.contains(p.id)).toList();

  void enterSelecting() {
    if (_selecting) return;
    _selecting = true;
    notifyListeners();
  }

  void exitSelecting() {
    if (!_selecting) return;
    _selecting = false;
    notifyListeners();
  }

  void toggle(String id) {
    if (!_picked.remove(id)) _picked.add(id);
    notifyListeners();
  }

  void pickAll() {
    _picked
      ..clear()
      ..addAll(_all.map((p) => p.id));
    notifyListeners();
  }

  void pickNone() {
    _picked.clear();
    notifyListeners();
  }

  /// 勾掉/勾上一整天。**按天操作是手机上最省事的批量方式** ——
  /// "第三天全是在车上拍的，不要了"是真实会发生的想法，
  /// 而让用户在三寸屏幕上点掉四十张不是。
  void toggleDay(List<PhotoRecord> dayPhotos) {
    final allPicked = dayPhotos.every((p) => _picked.contains(p.id));
    for (final p in dayPhotos) {
      if (allPicked) {
        _picked.remove(p.id);
      } else {
        _picked.add(p.id);
      }
    }
    notifyListeners();
  }
}
