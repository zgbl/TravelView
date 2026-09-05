# TravelView

把手机里的照片变成一个**开放的照片库**，并从库里生成可分享的旅行回顾。

- 备份 = 往库里写
- 游记 = 从库里读

- 使用说明：`docs/user-manual.md`（**改快捷键或鼠标行为必须同步更新它**）
- 设计文档：`Design/`，先读 `architecture.md`

## 目录结构

```
packages/
  tv_core/          纯 Dart 核心引擎（哈希 / 落盘 / sidecar / catalog / 校验）
                    不依赖 Flutter，手机端和桌面端共用同一份
  tv_ui/            共享 Widget（手机与桌面复用）
apps/
  tv_app/           Flutter 手机端 (iOS / Android)
  tv_desktop/       Flutter Desktop (macOS)
web/                分享站（发布出去的游记页面）
tools/
  devsink/          开发期产物回收服务
  spikes/           技术验证小程序
  pandoc/           中文 PDF 转换配置
  md2pdf.sh         Markdown -> PDF
  md-lint.py        Markdown 兼容性检查
test-output/        真机测试产物（runs/ 不入库）
Design/             设计文档
```

## 快速开始

```bash
# 核心引擎的单元测试（不需要手机、不需要 Flutter）
cd packages/tv_core
dart pub get
dart test

# 命令行试玩：把一个文件夹导入照片库
dart run bin/tv.dart import /tmp/mylib ~/Pictures/some_folder
dart run bin/tv.dart rebuild /tmp/mylib     # 删掉索引也能完整重建
dart run bin/tv.dart verify  /tmp/mylib     # 逐个重算哈希校验
dart run bin/tv.dart stats   /tmp/mylib
```
