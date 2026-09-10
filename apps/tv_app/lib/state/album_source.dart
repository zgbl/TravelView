import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

/// 手机端的 [StorySource]：照片在系统相册里。
///
/// [sourceOf] 直接返回资产 id —— 手机上**没有稳定的文件路径**可给
/// （iOS 的原件可能还在 iCloud 上没下载下来），`MobileImageOps` 认的
/// 也正是资产 id。导出器不需要知道这个区别。
class AlbumSource implements StorySource {
  final Map<String, PhotoRecord> _byId;

  AlbumSource(Iterable<PhotoRecord> photos)
      : _byId = {for (final p in photos) p.id: p};

  @override
  PhotoRecord? byId(String id) => _byId[id];

  @override
  String? sourceOf(String id) => _byId.containsKey(id) ? id : null;
}
