import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// App 在手机上的**临时工作目录**。
///
/// 这是手机端唯一会往磁盘上写东西的地方。三条铁律：
///
/// 1. **绝不碰系统相册里的原件。** 用户的照片是用户的，App 只读。
///    要缩放、要剥元数据、要打包，都在这个目录里做副本。
/// 2. **里面的东西全都可以随时删掉重建。** 缩小的待上传图、Story 打包产物、
///    缩略图缓存 —— 丢了顶多重做一遍，不会丢用户的任何数据。
/// 3. **不依赖任何外部设备。** 开发期用 USB 连电脑是给我们看日志用的，
///    真实用户手上只有一部手机。所有中间产物都落在这里，发布直接从这里上传。
///
/// 放在**系统的缓存目录**（iOS 的 Caches / Android 的 cacheDir）而不是
/// Documents：这类目录不会被备份进 iCloud（几百 MB 的派生图备份上去毫无意义），
/// 而且手机空间紧张时系统可以自己清掉。**代价是随时可能被清空**，所以
/// 每次用之前都要检查文件还在不在，不能把它当持久存储 —— 草稿、设置这些
/// 要留住的东西存在 `AppSettings` 那边。
class Workspace {
  Workspace._(this.root);

  final Directory root;

  static Workspace? _instance;
  static Workspace get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('Workspace 还没初始化，main() 里要先 await Workspace.init()');
    }
    return i;
  }

  /// 在 `main()` 里调一次。会顺手清掉上次运行留下的垃圾。
  static Future<Workspace> init() async {
    final base = await getTemporaryDirectory();
    final root = Directory(p.join(base.path, 'tv_work'));
    await root.create(recursive: true);
    final w = Workspace._(root);
    _instance = w;
    // 不 await：清理是尽力而为的事，不该让用户多等一秒看到首屏
    unawaited(w.sweep());
    return w;
  }

  // ---- 三类产物，各有各的目录 ----

  /// 待上传的派生图（缩小 + 剥掉元数据）。一次发布一个子目录。
  Directory exportDir(String storyKey) =>
      Directory(p.join(root.path, 'export', _safe(storyKey)));

  /// Story 打包产物（index.html 和它引用的资源）。
  Directory bundleDir(String storyKey) =>
      Directory(p.join(root.path, 'bundle', _safe(storyKey)));

  /// 精选算法要用的小图。**只有算法读，不上屏** ——
  /// 界面上的缩略图直接问系统相册要，不落盘（见 AssetThumb）。
  Directory get analysisDir => Directory(p.join(root.path, 'analysis'));

  Future<Directory> ensure(Directory d) => d.create(recursive: true);

  /// 发布成功、或者用户放弃这一篇之后，把它的中间产物删掉。
  ///
  /// **发布完就删，不留着"万一还要用"** —— 派生图随时能重新生成，
  /// 而攒着不删会在用户的手机上悄悄堆出几个 GB。
  Future<void> dropStory(String storyKey) async {
    for (final d in [exportDir(storyKey), bundleDir(storyKey)]) {
      if (await d.exists()) {
        await d.delete(recursive: true);
      }
    }
  }

  /// 启动时清理：删掉超过 [maxAge] 没动过的东西。
  ///
  /// 为什么要有这个 —— 用户在发布中途杀掉 App 是很常见的事，
  /// 那一次的派生图就永远没人删了。按时间扫一遍是最省心的兜底。
  Future<void> sweep({Duration maxAge = const Duration(days: 3)}) async {
    try {
      if (!await root.exists()) return;
      final now = DateTime.now();
      await for (final e in root.list()) {
        if (e is! Directory) continue;
        await for (final sub in e.list()) {
          try {
            final stat = await sub.stat();
            if (now.difference(stat.modified) > maxAge) {
              await sub.delete(recursive: true);
            }
          } catch (_) {
            // 单个删不掉不影响其他的
          }
        }
      }
    } catch (_) {
      // 清理失败绝不能挡住 App 启动
    }
  }

  /// 某一类产物占了多少字节（'export' / 'bundle' / 'analysis'）。
  ///
  /// 分类显示是有意义的：用户看见"待上传的缩小图 180MB"能明白那是
  /// 一次发布留下的，看见笼统的"缓存 180MB"只会怀疑我们在偷存他的照片。
  Future<int> bytesOf(String kind) async {
    final d = Directory(p.join(root.path, kind));
    var total = 0;
    try {
      if (!await d.exists()) return 0;
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }

  /// 工作目录现在占了多少字节。
  Future<int> usedBytes() async {
    var total = 0;
    try {
      await for (final e in root.list(recursive: true, followLinks: false)) {
        if (e is File) {
          total += await e.length();
        }
      }
    } catch (_) {
      // 算不出来就当 0，这只是个显示值
    }
    return total;
  }

  /// 整个清空。用户在设置里按"清理缓存"时调。
  Future<void> clear() async {
    try {
      if (await root.exists()) await root.delete(recursive: true);
      await root.create(recursive: true);
    } catch (_) {}
  }

  /// storyKey 是日期范围拼出来的，理论上很干净，
  /// 但**凡是要拿去当文件名的字符串都得过一遍**，这是习惯问题。
  static String _safe(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
}
