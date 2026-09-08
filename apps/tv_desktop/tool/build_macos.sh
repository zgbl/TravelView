#!/usr/bin/env bash
# 打出可以直接安装的 macOS 包（.app + .dmg）。
#
#   ./tool/build_macos.sh
#
# 产物在 dist/ 下。
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="TravelView"
VERSION=$(grep '^version:' pubspec.yaml | head -1 | sed 's/version: *//' | cut -d+ -f1)
OUT="dist"
APP="build/macos/Build/Products/Release/$APP_NAME.app"

echo "==> 清一遍（跨版本的残留是最难查的一类构建错误）"
flutter clean
flutter pub get

echo "==> 编译 release"
flutter build macos --release

if [ ! -d "$APP" ]; then
  echo "没找到 $APP —— 检查 macos/Runner/Configs/AppInfo.xcconfig 里的 PRODUCT_NAME" >&2
  exit 1
fi

echo "==> 临时签名（ad-hoc）"
# **必须签，哪怕是 ad-hoc。** Apple Silicon 上完全没有签名的 .app
# 会被系统直接杀掉（"已损坏，应移到废纸篓"），而那句提示会让人以为是构建坏了。
# ad-hoc 签名不需要开发者账号，但也不能让别人免报警地打开 —— 见 README。
codesign --force --deep --sign - "$APP"

mkdir -p "$OUT"
DMG="$OUT/$APP_NAME-$VERSION-macos.dmg"
rm -f "$DMG"

echo "==> 打 DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
# 拖进 Applications 的那个快捷方式 —— 没有它，用户会直接在 DMG 里双击运行，
# 然后每次都要重新挂载磁盘映像才能打开
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo
echo "完成: $DMG"
echo "大小: $(du -h "$DMG" | cut -f1)"
echo
echo "自己安装: 打开 DMG，把 TravelView 拖进 Applications。"
echo "第一次打开会被 Gatekeeper 拦下（因为没有开发者签名）——"
echo "  右键点图标 → 打开 → 再点「打开」。只需要做这一次。"
