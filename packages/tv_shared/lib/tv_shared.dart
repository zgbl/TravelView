/// TravelView 应用层共享包。
///
/// **判断一段代码该不该放这里的标准只有一条：手机端和桌面端是不是同一份逻辑。**
///
///   - 纯算法、不依赖 Flutter 的 -> `tv_core`
///   - 两端同一份、但要用到 Flutter 或 dart:io 的 -> 这里
///   - 只有一端有的（多窗口、快捷键、MTP 读手机）-> 留在各自的 app 里
///
/// 平台差异走 [ImageOps]：这里只声明"要能读 EXIF、出缩略图、出派生图"，
/// 桌面端用 macOS 的 ImageIO 实现，手机端用各自系统的实现，
/// 共享代码不需要知道跑在哪个平台上。
library tv_shared;

export 'src/app_settings.dart';
export 'src/handle_rules.dart';
export 'src/image_ops.dart';
export 'src/l10n.dart';
export 'src/music.dart';
export 'src/projects.dart';
export 'src/story_exporter.dart';
export 'src/story_source.dart';
export 'src/web_template.dart';
