import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tv_shared/tv_shared.dart';

import 'story_draft.dart';

/// 用户为这一篇挑的配乐文件，存在手机上的那一份。
///
/// **手机端必须自己留一份，不能只记路径。** 桌面端可以（也特意）只记路径 ——
/// 那个文件躺在用户的硬盘上，一直在那儿，导出时再拷。手机上不行：
/// iOS 的文档选择器给我们的是一个临时收件箱副本，Android 拿到 `content://`
/// 之后也是先抄进缓存目录再把路径交出来，两者都可能被系统清掉。
/// 只记路径的话，用户挑完曲子、又挑了半天照片，真正导出时文件已经没了，
/// 而这件事只会在**按下发布之后**才暴露。
///
/// 存在**应用支持目录**，不是 `Workspace` 那个缓存目录：
/// 缓存目录系统随时可以自己清掉（见 workspace.dart 里那段说明），
/// 而这是用户亲手选的内容 —— 照片丢了能回相册重拿，曲子丢了就真没了。
class MusicStore {
  MusicStore._();

  /// 应用支持目录下的 `music/`。里面一个子目录一首曲子，
  /// 子目录名是导入那一刻的时间戳。
  ///
  /// **为什么要多一层子目录**: 用户完全可能挑两首都叫 `track.mp3`
  /// （从两个专辑文件夹里各挑一首）。平铺的话第二首会把第一首覆盖掉，
  /// 而界面上两首都在，用户要到发布之后才发现少了一首。
  /// 有了一层槽位，文件名就能原样保留 —— 界面显示的就是他认得的那个名字。
  static Directory get dir {
    final base = AppSettings.configDir;
    if (base == null) {
      throw StateError('AppSettings.configDir 还没设，main() 里要先赋值');
    }
    return Directory(p.join(base.path, 'music'));
  }

  /// 把用户挑中的文件拷进沙盒，返回存下来的路径。失败返回 null。
  ///
  /// 后缀在白名单里才收 —— 选择器是按类型过滤的，但那是**过滤器不是闸门**，
  /// Android 上换个文件管理器就能绕过。真正的闸门在这里，
  /// 以及导出时 StoryExporter 再查一遍。
  ///
  /// 名字不叫 import —— 那是 Dart 的关键字，用了编译都过不去。
  static Future<String?> copyIn(String srcPath) async {
    try {
      final ext = p.extension(srcPath).replaceAll('.', '').toLowerCase();
      if (!StoryDraft.audioExts.contains(ext)) return null;

      final src = File(srcPath);
      if (!await src.exists()) return null;

      final slot = Directory(
          p.join(dir.path, DateTime.now().millisecondsSinceEpoch.toString()));
      await slot.create(recursive: true);
      final dst = p.join(slot.path, _safeName(p.basename(srcPath)));
      await src.copy(dst);
      return dst;
    } catch (_) {
      // 存储满了、文件读不到 —— 交给调用方去说人话
      return null;
    }
  }

  /// 去掉这一首时把文件也删掉。**只删自己目录里的** ——
  /// 传进来的字符串理论上一定出自 [import]，但"凡是要拿去删的路径
  /// 都得先确认它在自己地盘上"是习惯问题，不是这次才需要。
  static Future<void> remove(String path) async {
    try {
      final root = dir.path;
      if (!p.isWithin(root, path)) return;
      final f = File(path);
      if (await f.exists()) await f.delete();
      final slot = f.parent;
      if (p.isWithin(root, slot.path) &&
          await slot.exists() &&
          await slot.list().isEmpty) {
        await slot.delete();
      }
    } catch (_) {}
  }

  /// 启动时扫一遍，删掉放了太久没动过的曲子。
  ///
  /// **用户中途放弃的那些曲子必须有人收尸。** 手机端的草稿只在内存里，
  /// App 一杀，界面上的引用就没了，但文件还躺在沙盒里 ——
  /// 一首 MP3 三五 MB，攒一年就是几百 MB，而且用户翻遍设置也找不出是谁占的。
  /// [maxAge] 给得比 Workspace 宽松得多：那边是随时能重算的派生图，
  /// 这边是用户自己选的东西，宁可多留几天。
  static Future<void> sweep({Duration maxAge = const Duration(days: 7)}) async {
    try {
      final d = dir;
      if (!await d.exists()) return;
      final now = DateTime.now();
      await for (final slot in d.list()) {
        if (slot is! Directory) continue;
        try {
          if (now.difference((await slot.stat()).modified) > maxAge) {
            await slot.delete(recursive: true);
          }
        } catch (_) {
          // 单个删不掉不影响其他的
        }
      }
    } catch (_) {
      // 清理失败绝不能挡住 App 启动
    }
  }

  /// 文件名原样保留，只挡两种东西: 路径分隔符（会把文件写到目录外面去），
  /// 和长到文件系统装不下的名字。中文、空格、emoji 都留着 ——
  /// 那是用户认得出这首歌的唯一线索。
  static String _safeName(String name) {
    var s = name.replaceAll(RegExp(r'[/\\]'), '_').trim();
    if (s.isEmpty || s == '.' || s == '..') s = 'track';
    if (s.length > 80) {
      final ext = p.extension(s);
      s = s.substring(0, 80 - ext.length) + ext;
    }
    return s;
  }
}
