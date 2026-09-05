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
  DateTime updatedAt;

  Project({
    required this.name,
    this.rangeStart,
    this.rangeEnd,
    this.pickAlbum = '精选',
    this.clusterPreset = 'road',
    this.view = 0,
    this.note = '',
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
