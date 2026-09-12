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

# TravelView 构建与分发速查

> **最后更新：2026-09-11**
> 改任何构建命令、脚本或分发方式，必须同时改这份文档。
> 深入的平台配置（沙盒权限、Inno Setup、跨平台路径坑）见 `Design/build-and-package.md`。

---

## 0. 先分清三种场景

这三件事命令不同、产物不同、用途不同，**混用是最常见的浪费时间的方式**：

| 场景 | 谁用 | 要什么 | 版本号 |
|---|---|---|---|
| **① 开发调试** | 你自己，边改边看 | 热重载，装到连着的手机/本机 | 不动 |
| **② 内测分发** | 你、朋友、测试机 | 一个能发出去的文件 | 要 bump |
| **③ 正式发布** | 真实用户 | 商店审核 / 官网下载 | 要 bump + 签名 |

下面按这三种场景分开写。

---

## 1. 场景①：开发调试（版本号不动）

### Android 真机（USB 连着）

```
cd ~/Codes/Github3/TravelView/apps/tv_app
```
```
fvm flutter run -d 3B6F63E7SX2M36J2
```

**是的，你原来那条命令没变，继续用。** 手机端（`apps/tv_app`）目录下有
`.fvmrc`，所以必须带 `fvm`；桌面端（`apps/tv_desktop`）没有 `.fvmrc`，
用系统的 `flutter` 就行。

设备 id 记不住时先列一遍：

```
fvm flutter devices
```

### iPhone 真机（无线连着的 TXY12ProMax）

```
cd ~/Codes/Github3/TravelView/apps/tv_app
```
```
fvm flutter run -d 00008101-001D655C01F2001E
```

### macOS 桌面端

```
cd ~/Codes/Github3/TravelView/apps/tv_desktop
```
```
flutter run -d macos
```

### 只想把已经编好的包装到手机上（不跑调试）

```
cd ~/Codes/Github3/TravelView/apps/tv_app
```
```
fvm flutter install -d 3B6F63E7SX2M36J2
```

---

## 2. 场景②③：出给用户的安装包

**统一入口是 `tools/build.sh`，不要手工跑 `flutter build`。**
版本号 +1 是这个脚本的第一步 —— 忘记 bump 的代价是上传被商店拒绝，
而那通常发生在你已经等了二十分钟编译之后。

脚本会自己判断该用 `fvm flutter` 还是 `flutter`（看那个目录里有没有 `.fvmrc`），
你不用记。

### Android

```
cd ~/Codes/Github3/TravelView
```
```
bash tools/build.sh android
```

产出两个文件，**两个都要，用途不同**：

- `dist/TravelView-0.6.2.aab` —— 传 Google Play 用。Play 只收 aab，
  它会按机型拆分成不同的 apk 下发。**用户不能直接装 aab。**
- `dist/TravelView-0.6.2.apk` —— 直接发给人装、放官网下载用。
  用户要在系统设置里允许「安装未知来源应用」。

正式上架前还要配**签名密钥**（`android/key.properties` + keystore）。
现在用的是 debug 签名，能装能测，但 Play 不收，而且
**一旦用某个 key 上架，之后永远只能用同一个 key**，丢了就只能换包名重来。

### iOS

```
cd ~/Codes/Github3/TravelView
```
```
bash tools/build.sh ios
```

**iOS 没有「给用户下载的安装包」这回事。** Apple 不允许从网页装 app，
用户拿到 app 只有两条路：

- **TestFlight**（内测，最多 10000 人）—— 上传后审核几小时，测试者装
  TestFlight app 接受邀请。内测阶段就用这个。
- **App Store**（正式）—— 完整审核，几天。

两条路都要 **Apple Developer 账号（$99/年）**，都要在 Xcode 里配好
签名和描述文件。脚本跑完会停在 archive，之后的上传在 Xcode 里做：

```
open ~/Codes/Github3/TravelView/apps/tv_app/ios/Runner.xcworkspace
```

Xcode → Product → Archive → Distribute App → TestFlight & App Store。

没配签名的话脚本会在 archive 这一步报错，这是正常的，不是脚本坏了。

### macOS 桌面端

```
cd ~/Codes/Github3/TravelView
```
```
bash tools/build.sh mac
```

产出 `dist/TravelView-0.6.2.dmg`，这就是发给用户的文件，双击装。

先装打 dmg 的工具（只需一次）：

```
brew install create-dmg
```

没装的话脚本不会失败，只是跳过打 dmg，留下 `.app`。

**签名问题**：现在是未签名的。别人下载后打开会被 Gatekeeper 拦
（「无法打开，因为无法验证开发者」），要右键 →「打开」才能运行。
正式对外分发需要 Apple 开发者账号做签名 + 公证（notarization）。
**内测阶段可以先不管，但要在下载页写清楚怎么绕过**，否则十个人有八个
以为是病毒。

### Windows 桌面端

**必须在那台 Win10 机器上跑，不能从 Mac 交叉编译。**
先在那台机器上 pull 最新代码 —— 否则两台机器各自 bump，build 号会打架。

在 Git Bash 里：

```
cd /c/path/to/TravelView
```
```
git pull
```
```
bash tools/build.sh win
```

产出两样东西：

- `apps/tv_desktop/build/windows/x64/runner/Release/` —— **整个文件夹**才是
  完整程序，只拷 exe 出去跑不起来。
- 同目录下的 `.msix` —— 双击安装的安装包。

msix 现在用自签名证书，用户安装时 Windows 会弹安全警告。要做到不弹警告，
得买代码签名证书（一年几百美元）。要发给普通用户、又不想买证书，
用 Inno Setup 打成传统的 `setup.exe` 更合适（见
`Design/build-and-package.md` 第 3 节）。

---

## 3. 版本号

**唯一真相是根目录的 `VERSION` 文件**，两个 app 的 pubspec 里那行是它的副本。
手工改 pubspec 会在下一次 bump 时被覆盖 —— 这是故意的。

```
version=0.6.1   # 对外显示，改 base（0.6 → 0.7）时手工改这一行
build=1         # 只增不减的构建号，不要手工改
```

**桌面端和手机端永远同版本。** 用户不会分「我装的是桌面 0.6.3 还是手机 0.6.7」，
你收到 bug 报告时也只有一个号要对。

只动版本号、不编译：

```
cd ~/Codes/Github3/TravelView
```
```
python3 tools/bump-build.py
```

其它用法：

- `bash tools/build.sh mac --no-bump` —— 用当前版本重出一次
  （上一次传挂了、要原号重来时用）
- `bash tools/build.sh android --set 0.7.0` —— 顺手换 base，build 照样 +1

### 界面上在哪儿看得到

- 手机端：我的 → 版本 → `0.6.2 (2)`
- 桌面端：底部状态栏最右边 → `v0.6.2 (2)`，可选中复制

括号里是构建号。两处都从 `package_info_plus` 读，**不写死**。

---

## 4. 上线前还欠的东西

按咬人的先后排：

1. **Android 正式签名 key** —— 不配就上不了 Play，而且 key 丢了要换包名重来
2. **Apple Developer 账号** —— iOS 没有它一步都走不了，注册审核要几天，
   越早交越好
3. **macOS 签名 + 公证** —— 不做的话下载页得写一段「怎么绕过 Gatekeeper」
4. **Windows 代码签名证书** —— 可以最后做，自签名先顶着
