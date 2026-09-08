# 打包桌面端

两个平台各出一个能自己安装的包。

## 结论先说：Windows 现在只能跑起来，不能用

`lib/native/native_bridge.dart` 里：

```dart
static bool get supported => Platform.isMacOS;
```

原生层（读 EXIF/GPS、生成缩略图、导出网页图、算精选信号、连手机）
**只有 macOS 的实现**（`macos/Runner/PhoneBridge.swift`）。Windows 上这些调用
全部安全降级成"什么都不做"，所以 Windows 版能编译、能启动、界面完整，但：

- 照片没有缩略图
- 读不到拍摄时间和 GPS → **分不出站、画不出路线**
- 导不出网页图 → **发布出去是空的**

也就是说，Windows 包现在只能验证"界面在 Windows 上长什么样、会不会崩"，
不能验证产品功能。补齐的办法见最后一节。

---

## macOS

### 需要装什么

| | |
|---|---|
| Xcode | App Store 装，装完跑一次 `sudo xcodebuild -license accept` |
| Flutter | `flutter doctor` 全绿（至少 macOS 那一行绿） |
| CocoaPods | `sudo gem install cocoapods`，或 `brew install cocoapods` |

### 打包

```bash
cd apps/tv_desktop
./tool/build_macos.sh
```

产物：`dist/TravelView-0.1.0-macos.dmg`

### 安装

打开 DMG，把 TravelView 拖进 Applications。

**第一次打开一定会被拦。** 因为没有 Apple 开发者签名，系统会说
"无法打开，因为无法验证开发者"。做法：

> 右键点 TravelView → **打开** → 再点一次「打开」

只需要做这一次，之后正常双击。

如果看到的是**"已损坏，应移到废纸篓"**，那是另一回事：
Apple Silicon 上完全没签名的 app 会被直接杀掉。构建脚本里已经做了
ad-hoc 签名（`codesign --sign -`）来避免这个；万一还是出现：

```bash
xattr -dr com.apple.quarantine /Applications/TravelView.app
```

### 想给别人装（以后）

要免掉上面那一步，需要 Apple Developer 账号（$99/年）做
**签名 + 公证（notarize）**。自己测试不需要。

---

## Windows

### 需要装什么

| | |
|---|---|
| **Visual Studio 2022** | 社区版即可，安装时**必须勾选「使用 C++ 的桌面开发」**。只装 VS Code 没用 —— Flutter 的 Windows 构建要 MSVC 编译器和 Windows SDK |
| Flutter | `flutter doctor` 里 "Visual Studio" 那一行要绿 |
| Git for Windows | Flutter 自己要用 |

装完确认：

```powershell
flutter doctor -v
flutter config --enable-windows-desktop
```

### 打包

```powershell
cd apps\tv_desktop
powershell -ExecutionPolicy Bypass -File tool\build_windows.ps1
```

产物：`dist\TravelView-0.1.0-windows.zip`

### 安装

解压到任意目录，双击 `TravelView.exe`。

**第一次运行 SmartScreen 会拦**（没有代码签名证书）：
点「更多信息」→「仍要运行」。

> zip 里的**每一个文件都要留着**。Flutter 的 Windows 产物是
> `TravelView.exe` + `flutter_windows.dll` + `data\` 目录，
> 单独把 exe 拷出来就是双击没反应、也不报错。

### .msix（可选）

`pubspec.yaml` 里已经配好了 `msix_config`：

```powershell
dart run msix:create
```

但自签名的 msix 要先把证书装进「受信任的根证书颁发机构」才装得上，
自己测试用 zip 更省事。以后要上 Microsoft Store 才需要它。

---

## 版本号

改 `pubspec.yaml` 的 `version:`，两个平台的构建脚本都从这里读：

```yaml
version: 0.1.0+1
#        ^^^^^  给人看的版本，会进文件名和 DMG 卷标
#              ^ 构建号，每次发布 +1
```

Windows 的 msix 还要同步改 `msix_config.msix_version`（必须是四段，
如 `0.1.0.0`）——**这两个不一致时 msix 会打出上一个版本号**，很难发现。

---

## 把 Windows 真正跑起来（下一步）

要让 Windows 版能用，`NativeBridge` 需要一条非 macOS 的实现路径。
两个方向：

**A. 纯 Dart 兜底**（推荐先做这个）
用 `package:image` 解码缩放、`package:exif` 读元数据，在 Dart 里实现
`readMetadata` / `makeThumbnail` / `exportWeb` / `analyze`。
好处是一份代码所有平台都能跑、不用写 C++；代价是慢（几千张照片会明显
比 macOS 慢），而且 **HEIC 解不了** —— iPhone 照片在 Windows 上会失败，
需要给一句明确提示，而不是静静地什么都不显示。

**B. Windows 原生插件**
用 WIC（Windows Imaging Component）写一个 C++ plugin，性能和 macOS 一个量级，
HEIC 在装了 HEIF 扩展的 Windows 上也能解。工作量大得多。

建议先做 A，把 Windows 版变成"能用但慢"，再看有没有人真的在 Windows 上用。
