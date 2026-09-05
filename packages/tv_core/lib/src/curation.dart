import 'dart:math' as math;

import 'models.dart';
import 'route.dart';

/// 感知哈希的汉明距离。距离越小越像。
/// 两张几乎相同的照片通常 <= 6，明显不同的一般 > 20。
int hammingDistance(String a, String b) {
  if (a.length != b.length) return 64;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    final x = int.tryParse(a[i], radix: 16);
    final y = int.tryParse(b[i], radix: 16);
    if (x == null || y == null) return 64;
    var v = x ^ y;
    while (v != 0) {
      d += v & 1;
      v >>= 1;
    }
  }
  return d;
}

/// 一张照片的得分与理由。
///
/// **理由必须能给用户看** —— 自动精选如果是黑盒，用户就不会信任它，
/// 也就不敢把挑图交给它。
class PhotoScore {
  final PhotoRecord photo;
  final double total;
  final Map<String, double> breakdown;

  const PhotoScore(this.photo, this.total, this.breakdown);

  String get topReason {
    if (breakdown.isEmpty) return '';
    final sorted = breakdown.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    return sorted.first.key;
  }
}

class CurationOptions {
  /// 目标张数。null 表示按数量自动决定（约 sqrt(n)，上下限见下）
  final int? targetCount;
  final int minCount;
  final int maxCount;

  /// 感知哈希距离小于等于这个值就算"同一张"，用于去重
  final int similarityThreshold;

  /// 同一个时间窗口内最多选几张，避免全都挤在同一分钟
  final Duration diversityWindow;
  final int maxPerWindow;

  /// 没有感知哈希时的兜底: 间隔小于这个时间的照片一律当作连拍。
  /// 信号还没算出来的库（或视频）靠它也能去掉大部分重复。
  final Duration burstWindow;

  /// 判重的时间上限。**隔得够久的照片，长得再像也不是同一张** ——
  /// 同一个山谷早上和傍晚各拍一张，是两个时刻，不能折叠成一张。
  final Duration dedupWindow;

  const CurationOptions({
    this.targetCount,
    this.minCount = 3,
    this.maxCount = 10,
    this.similarityThreshold = 8,
    this.diversityWindow = const Duration(minutes: 10),
    this.maxPerWindow = 2,
    this.burstWindow = const Duration(seconds: 12),
    this.dedupWindow = const Duration(minutes: 10),
  });
}

/// 一组近似重复的照片（连拍、同一景物反复拍）。
class DuplicateGroup {
  final List<PhotoScore> members;
  const DuplicateGroup(this.members);

  PhotoScore get best => members.first;
  int get length => members.length;
}

/// 一站的精选结果。
class StopSelection {
  final Stop stop;
  final PhotoRecord? hero;
  final List<PhotoRecord> selected;
  final List<DuplicateGroup> groups;
  final int totalPhotos;

  const StopSelection({
    required this.stop,
    required this.hero,
    required this.selected,
    required this.groups,
    required this.totalPhotos,
  });

  int get duplicatesRemoved => totalPhotos - groups.length;
}

/// 自动精选。**第一版完全不用 AI。**
///
/// 用的全是拍摄时就已经存在的信号: 清晰度、分辨率、人脸数、构图、
/// 感知哈希、时间分布。这些足以解决最痛的那个问题 ——
/// 91 张里有一半是同一个街景、同一个自拍、同一段路。
///
/// 产出是"建议"，不是"决定": UI 上一律预选好让用户确认或改，
/// 绝不悄悄替用户丢照片。
class Curator {
  final CurationOptions options;
  const Curator({this.options = const CurationOptions()});

  /// 给一批照片打分。分数是**组内相对**的 ——
  /// 不同相机、不同光线下的绝对值没有可比性。
  List<PhotoScore> score(List<PhotoRecord> photos) {
    if (photos.isEmpty) return const [];

    final sharps = photos
        .map((p) => p.sharpness)
        .whereType<double>()
        .toList()
      ..sort();
    final pixels = photos.map((p) => p.pixels).where((v) => v > 0).toList()
      ..sort();

    return photos.map((p) {
      final b = <String, double>{};

      // 清晰度: 组内百分位。模糊、手抖的照片在这里被压下去
      if (p.sharpness != null && sharps.length > 1) {
        b['清晰'] = _percentile(sharps, p.sharpness!) * 3.0;
      }

      // 分辨率: 截图和网上存的图通常明显更小
      if (p.pixels > 0 && pixels.length > 1) {
        b['分辨率'] = _percentile(pixels.map((e) => e.toDouble()).toList(),
                p.pixels.toDouble()) *
            1.0;
      }

      // 曝光: 过曝或欠曝扣分
      if (p.brightness != null) {
        final dev = (p.brightness! - 0.5).abs();
        b['曝光'] = (1.0 - (dev / 0.5)) * 1.2;
      }

      // 有人的照片更值得放进旅行回顾
      final faces = p.faceCount ?? 0;
      if (faces > 0) {
        b['有人'] = math.min(faces, 3) * 0.8;
      }

      // 横构图更适合做页面上的大图
      if (p.isLandscape) b['横构图'] = 0.4;

      // 截图基本不属于旅行内容
      if (p.isScreenshot) b['截图'] = -4.0;

      // 用户已经编辑过的版本，说明他本来就更中意这张
      if (p.editOf != null) b['已修图'] = 1.5;

      // 已经手动选取过的，绝对优先
      if (p.tags.any((t) => t.kind == 'pick')) b['已手选'] = 6.0;

      final total = b.values.fold<double>(0, (a, v) => a + v);
      return PhotoScore(p, total, b);
    }).toList();
  }

  /// 按感知哈希 + 时间邻近，把连拍和重复拍摄归成一组。
  List<DuplicateGroup> groupDuplicates(List<PhotoScore> scored) {
    final sorted = List<PhotoScore>.from(scored)
      ..sort((a, b) => a.photo.takenAt.compareTo(b.photo.takenAt));

    final groups = <List<PhotoScore>>[];
    for (final s in sorted) {
      var placed = false;
      for (final g in groups) {
        if (_isDuplicate(g, s)) {
          g.add(s);
          placed = true;
          break;
        }
      }
      if (!placed) groups.add([s]);
    }

    return groups.map((g) {
      g.sort((a, b) => b.total.compareTo(a.total));
      return DuplicateGroup(List.unmodifiable(g));
    }).toList();
  }

  /// **只和组的代表比，不和每个成员比。** 挨个比会连锁: A 像 B、B 像 C，
  /// 于是 A 和 C 也被并进同一组，一整天的照片能这样滚成一堆。
  bool _isDuplicate(List<PhotoScore> group, PhotoScore s) {
    final m = group.first;
    final apart = s.photo.takenAt.difference(m.photo.takenAt).abs();

    // 兜底: 十几秒内连着拍的，不看内容也按连拍处理。
    // 信号还没算出来的照片全靠这条，否则"精选"出来还是一堆重复。
    if (apart <= options.burstWindow) return true;

    // 隔得够久就不再判重，哪怕内容很像 —— 那是另一个时刻。
    if (apart > options.dedupWindow) return false;

    final ph = s.photo.phash;
    final mp = m.photo.phash;
    if (ph == null || mp == null) return false;
    // 时间隔得越近，判重可以越宽松
    final threshold = apart < const Duration(seconds: 30)
        ? options.similarityThreshold + 4
        : options.similarityThreshold;
    return hammingDistance(ph, mp) <= threshold;
  }

  /// 一站的完整精选流程: 打分 -> 去重 -> 按分排序 -> 保证时间分散 -> 选封面
  StopSelection curateStop(Stop stop, List<PhotoRecord> photos) {
    if (photos.isEmpty) {
      return StopSelection(
        stop: stop,
        hero: null,
        selected: const [],
        groups: const [],
        totalPhotos: 0,
      );
    }

    final scored = score(photos);
    final groups = groupDuplicates(scored)
      ..sort((a, b) => b.best.total.compareTo(a.best.total));

    final target = _targetCount(groups.length);
    final picked = <PhotoScore>[];
    final windowCount = <int, int>{};

    // 第一轮: 分数优先，但限制同一时间窗口的数量，避免全挤在同一分钟
    for (final g in groups) {
      if (picked.length >= target) break;
      final key = g.best.photo.takenAt.millisecondsSinceEpoch ~/
          options.diversityWindow.inMilliseconds;
      if ((windowCount[key] ?? 0) >= options.maxPerWindow) continue;
      picked.add(g.best);
      windowCount[key] = (windowCount[key] ?? 0) + 1;
    }

    // 第二轮: 如果因为分散限制没选够，放宽再补
    if (picked.length < target) {
      for (final g in groups) {
        if (picked.length >= target) break;
        if (picked.contains(g.best)) continue;
        picked.add(g.best);
      }
    }

    picked.sort((a, b) => a.photo.takenAt.compareTo(b.photo.takenAt));

    return StopSelection(
      stop: stop,
      hero: _pickHero(picked),
      selected: picked.map((e) => e.photo).toList(),
      groups: groups,
      totalPhotos: photos.length,
    );
  }

  /// 封面: 分数最高的那张，横构图额外加分（页面上的大图更适合横的）
  PhotoRecord? _pickHero(List<PhotoScore> picked) {
    if (picked.isEmpty) return null;
    var best = picked.first;
    var bestScore = double.negativeInfinity;
    for (final s in picked) {
      final v = s.total + (s.photo.isLandscape ? 1.5 : 0);
      if (v > bestScore) {
        bestScore = v;
        best = s;
      }
    }
    return best.photo;
  }

  int _targetCount(int groupCount) {
    if (options.targetCount != null) {
      return math.min(options.targetCount!, groupCount);
    }
    if (groupCount <= options.minCount) return groupCount;
    final auto = math.sqrt(groupCount).round();
    return auto.clamp(options.minCount, options.maxCount).clamp(1, groupCount);
  }

  static double _percentile(List<double> sortedAsc, double v) {
    if (sortedAsc.isEmpty) return 0.5;
    var below = 0;
    for (final x in sortedAsc) {
      if (x < v) below++;
    }
    return below / sortedAsc.length;
  }
}
