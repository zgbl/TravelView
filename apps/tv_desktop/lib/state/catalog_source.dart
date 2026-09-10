import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tv_core/tv_core.dart';
import 'package:tv_shared/tv_shared.dart';

/// 桌面端的 [StorySource]：照片在一个真实的照片库目录里。
///
/// 手机端那份实现返回的是系统相册的资产 id，这里返回的是绝对文件路径 ——
/// 两边都直接喂给 `ImageOps.exportWeb`，各自那份实现认得自己那种。
class CatalogSource implements StorySource {
  final Directory libraryRoot;
  final Catalog catalog;

  const CatalogSource({required this.libraryRoot, required this.catalog});

  @override
  PhotoRecord? byId(String id) => catalog.byId(id);

  @override
  String? sourceOf(String id) {
    final rel = catalog.relPathOf(id);
    if (rel == null) return null;
    return p.joinAll([libraryRoot.path, ...p.posix.split(rel)]);
  }
}
