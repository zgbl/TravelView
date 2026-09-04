# tv_core

TravelView 照片库核心引擎。纯 Dart，不依赖 Flutter，手机端与桌面端共用。

## 五条架构原则（代码要守住的）

1. **文件是唯一真相** —— 原件是普通文件，放在按时间组织的目录里
2. **一张照片只存一份字节** —— 分类靠 tag，不靠复制
3. **索引可完全重建** —— sidecar JSON 是真相，catalog 是派生缓存
4. **用户可随便动文件，库靠内容哈希自愈**
5. **视图层不依赖任何文件系统特性**（exFAT 没有软链接）

`test/library_test.dart` 里每条原则都有对应的测试，改代码前先看它们。

## 硬约束

**catalog 里永远不允许存在唯一一份的信息。** 任何写进索引的内容，
必须同时落进对应目录的 `.tvmeta.json`。违反这条，`rebuild` 就会丢数据，
"你随时可以不要我"的承诺就成了空话。

## 模块

| 文件 | 职责 |
|---|---|
| `fingerprint.dart` | 内容寻址：快速指纹 + 全量哈希 |
| `layout.dart` | 磁盘布局：目录、文件名、exFAT 安全的字符清理 |
| `sidecar.dart` | `.tvmeta.json` 读写（真相层，原子写入） |
| `catalog.dart` | 派生索引、查询、分面、JSONL 镜像、`rebuild` |
| `importer.dart` | 导入：去重、防覆盖、元数据合并 |
| `verifier.dart` | 校验：重算哈希比对 |

## 尚未实现（下一步）

- SQLite 后端（当前是内存索引 + JSONL，接口不变）
- EXIF/GPS 解析（在手机端做，通过参数传进来）
- 停留点聚类 -> 行程节点
- 视图导出：`index.html` / `.webloc` / symlink / copy
- Live Photo 配对、iOS 编辑版本关联
