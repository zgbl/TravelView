import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tv_core/tv_core.dart';

/// 一份"做到一半的工作"。
///
/// 一个照片库里可以有很多个 —— 横穿美国的总报告、其中某一段、某个城市的一天。
/// 它只记录"怎么看这个库"：时间范围、挑选用的专辑名、聚类粒度、当前视图。
/// **不含任何照片数据** —— 照片和选取标签的真相始终在 sidecar 里，
/// 所以删掉草稿不会丢任何东西。
class Project {
  String name;
  DateTime? rangeStart;
  DateTime? rangeEnd;
  String pickAlbum;
  String clusterPreset;
  int view;
  String note;

  /// 上次发布到网站后服务器给的 Story id。
  /// 有它就说明这份草稿在网上已经有一篇了，再次发布是**更新那一篇**，
  /// 链接不变、也不会再扣一次额度。
  /// 用户选定的片头封面照片 id。空 = 用自动挑的那张
  String coverPhotoId;

  /// Story Cover 的形态: auto（默认，由内容决定）/ map / mapcard / photo
  String coverMode;

  /// 距离单位: auto（按行程所在的国家）/ mi 英里 / km 公里。
  /// **中英文两个版本用同一个单位** —— 同一篇游记里中文说 78 公里、
  /// 英文说 48 miles，虽然两个数都对，但读者对不上账。
  String units;

  /// 发布出去的标题。**和草稿名字是两回事** ——
  /// 草稿名是给自己找东西用的（"横穿美国-第二版"），
  /// 标题是封面上最大的那行字、也是分享卡片的第一行，读者只看得到它。
  /// 空 = 用草稿名兜底。
  String storyTitle;
  String storySubtitle;

  String publishedStoryId;
  String publishedUrl;

  /// 上次发布的那份产物的指纹（见 ExportResult.storyKey）。
  /// 和当前要发的对不上，就说明这是另一趟行程，**不能更新，只能新发一篇**。
  String publishedKey;

  /// 上次发布时的标题，让用户知道"更新"会覆盖掉哪一篇
  String publishedTitle;

  DateTime updatedAt;

  Project({
    required this.name,
    this.rangeStart,
    this.rangeEnd,
    this.pickAlbum = '精选',
    this.clusterPreset = 'road',
    this.view = 0,
    this.note = '',
    this.coverPhotoId = '',
    this.coverMode = 'auto',
    this.units = 'auto',
    this.storyTitle = '',
    this.storySubtitle = '',
    this.publishedStoryId = '',
    this.publishedUrl = '',
    this.publishedKey = '',
    this.publishedTitle = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'name': name,
        'rangeStart': rangeStart?.toIso8601String(),
        'rangeEnd': rangeEnd?.toIso8601String(),
        'pickAlbum': pickAlbum,
        'clusterPreset': clusterPreset,
        'view': view,
        'note': note,
        'coverPhotoId': coverPhotoId,
        'coverMode': coverMode,
        'units': units,
        'storyTitle': storyTitle,
        'storySubtitle': storySubtitle,
        'publishedStoryId': publishedStoryId,
        'publishedUrl': publishedUrl,
        'publishedKey': publishedKey,
        'publishedTitle': publishedTitle,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        name: j['name'] as String? ?? '未命名',
        rangeStart: _dt(j['rangeStart']),
        rangeEnd: _dt(j['rangeEnd']),
        pickAlbum: j['pickAlbum'] as String? ?? '精选',
        clusterPreset: j['clusterPreset'] as String? ?? 'road',
        view: (j['view'] as num?)?.toInt() ?? 0,
        note: j['note'] as String? ?? '',
        coverPhotoId: j['coverPhotoId'] as String? ?? '',
        coverMode: j['coverMode'] as String? ?? 'auto',
        units: j['units'] as String? ?? 'auto',
        storyTitle: j['storyTitle'] as String? ?? '',
        storySubtitle: j['storySubtitle'] as String? ?? '',
        publishedStoryId: j['publishedStoryId'] as String? ?? '',
        publishedUrl: j['publishedUrl'] as String? ?? '',
        publishedKey: j['publishedKey'] as String? ?? '',
        publishedTitle: j['publishedTitle'] as String? ?? '',
        updatedAt: _dt(j['updatedAt']) ?? DateTime.now(),
      );

  static DateTime? _dt(Object? v) => v is String ? DateTime.tryParse(v) : null;
}

/// 草稿存在**照片库里**，不是应用配置里 ——
/// 把库拷到移动硬盘、换台电脑打开，工作进度跟着一起走。
class ProjectStore {
  final Directory libraryRoot;
  ProjectStore(this.libraryRoot);

  File get file =>
      File(p.join(libraryRoot.path, LibraryLayout.catalogDir, 'projects.json'));

  Future<List<Project>> load() async {
    try {
      if (!await file.exists()) return [];
      final list = jsonDecode(await file.readAsString()) as List;
      return list
          .whereType<Map>()
          .map((m) => Project.fromJson(Map<String, dynamic>.from(m)))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Project> projects) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert(projects.map((e) => e.toJson()).toList()));
    await tmp.rename(file.path);
  }
}
