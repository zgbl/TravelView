/// TravelView 照片库核心引擎。
///
/// 架构原则（见 Design/architecture.md）:
///   1. 文件是唯一真相 —— 原件以普通文件存在按时间组织的目录里
///   2. 一张照片只存一份字节 —— 分类靠 tag，不靠复制
///   3. 索引可完全重建 —— sidecar JSON 是真相，catalog 是派生缓存
///   4. 用户可随便动文件，库靠内容哈希自愈
///   5. 视图层不依赖任何文件系统特性
library;

export 'src/models.dart';
export 'src/fingerprint.dart';
export 'src/layout.dart';
export 'src/sidecar.dart';
export 'src/catalog.dart';
export 'src/importer.dart';
export 'src/verifier.dart';
