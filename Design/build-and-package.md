---
# 中文 PDF 字体 —— 必须写在文件里：VS Code 的 Pandoc 扩展只注入 Helvetica，不读外部配置文件。
CJKmainfont: "PingFang SC"
CJKoptions: "BoldFont=PingFang SC Semibold"
header-includes: |
  ```{=latex}
  \setCJKsansfont{PingFang SC}
  \setCJKmonofont{PingFang SC}
  \xeCJKDeclareCharClass{CJK}{"2010 -> "2027, "2190 -> "21FF, "2460 -> "24FF,
                              "2500 -> "257F, "25A0 -> "25FF, "2600 -> "27BF}
  ```
---

# TravelView 桌面端：编译与打包

## 0. 一次性：生成平台工程

我只写了 `lib/` 和 `pubspec.yaml`。macOS 和 Windows 的原生工程目录（Xcode 工程、
CMake 工程）必须由 Flutter 生成——在项目根目录执行一次：

```bash
cd apps/tv_desktop
flutter create --platforms=macos,windows \
  --org com.travelview --project-name tv_desktop .
```

`flutter create` 在已有目录上是**增量**的：它只补 `macos/`、`windows/` 这些缺失的部分，
不会覆盖我写好的 `lib/` 和 `pubspec.yaml`。

然后：

```bash
flutter pub get
flutter run -d macos          # 开发时跑这个，支持热重载
```

## 1. 环境要求

| | macOS (iMac M1) | Windows 10 桌面 |
|---|---|---|
| Flutter | stable，`flutter config --enable-macos-desktop` | `flutter config --enable-windows-desktop` |
| 编译器 | Xcode + CLI Tools | **Visual Studio 2022**，勾选「使用 C++ 的桌面开发」工作负载 |
| 验证 | `flutter doctor -v` 全绿 | 同左 |

**注意**：Windows 版**必须在 Windows 机器上编译**，无法从 Mac 交叉编译。
所以流程是：在 iMac 上写代码 -> 推 git -> 在 Win10 上 pull 并 build。

## 2. macOS 打包成 .app / .dmg

```bash
cd apps/tv_desktop
flutter build macos --release
# 产物: build/macos/Build/Products/Release/tv_desktop.app
```

做成可分发的 dmg：

```bash
brew install create-dmg
create-dmg --volname "TravelView" --window-size 520 380 \
  --icon-size 96 --app-drop-link 360 160 \
  TravelView-0.1.0.dmg \
  build/macos/Build/Products/Release/tv_desktop.app
```

**签名说明**：自己机器上跑不需要签名。发给别人时，未签名的 App 会被 Gatekeeper 拦下，
对方要右键「打开」才能运行。真要公开分发，需要 Apple 开发者账号（$99/年）做
签名 + 公证（notarization）。**现阶段不用管**。

**沙盒必须关掉或加权限**：Flutter 生成的 macOS 工程默认开启 App Sandbox，
沙盒下无法访问用户选择之外的文件夹。照片库这种要自由读写外部磁盘的应用，
需要编辑 `macos/Runner/DebugProfile.entitlements` 和 `Release.entitlements`：

```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

如果之后要直接扫描移动硬盘、而不是每次都让用户手选，就得把
`com.apple.security.app-sandbox` 设为 `false`（代价是不能上 Mac App Store，
但对独立分发没有影响）。

## 3. Windows 打包成安装包

```bash
cd apps\tv_desktop
flutter build windows --release
:: 产物: build\windows\x64\runner\Release\  （整个文件夹才是完整程序）
```

两种安装包，选一种：

**方案 A：MSIX（最省事）** —— `pubspec.yaml` 里已经配好了：

```bash
dart run msix:create
```
生成 `.msix`，双击安装。自签名证书装的时候 Windows 会警告，测试阶段可接受。

**方案 B：Inno Setup（更传统，用户更熟悉）** —— 装 Inno Setup 后写个 `.iss`，
把 `Release` 整个文件夹打进去，生成常见的 `setup.exe`。要发给普通用户建议用这个。

## 4. 跨平台注意事项（已经处理的）

- **索引里的路径一律用 `/` 分隔**。库可能放在移动硬盘上被两个系统轮流读写，
  路径分隔符不统一会直接打架。`Catalog.toPosix` 负责这件事。
- **文件名按 exFAT 最严格的规则清理**。移动硬盘基本都是 exFAT，
  它不允许 `\ / : * ? " < > |`，也不允许结尾是点。
- **Windows 的 260 字符路径上限**。文件名已限制在 180 字符内，留了余量。

## 5. 目前的已知限制

- **HEIC 不能显示**。Flutter 自带的解码器不认 HEIC，iPhone 的照片目前显示成
  带类型标签的占位块。JPEG/PNG 正常显示。解决要走平台通道调系统解码器
  （macOS 用 ImageIO，Windows 用 WIC），排在下一步。
- **还不能直连手机**。当前只能从文件夹导入。USB 直读见
  `architecture.md` 6.5 节，是接下来的重点。
- **EXIF 还没解析**。导入时用文件修改时间当拍摄时间，GPS 为空。
  这个可以先在桌面端用 Dart 的 EXIF 库补上，不必等手机端。
