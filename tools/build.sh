#!/usr/bin/env bash
# TravelView 出包。**版本号在这里自动 +1，不靠记性。**
#
#   bash tools/build.sh mac        macOS .app + .dmg
#   bash tools/build.sh win        Windows Release 目录 + .msix（必须在 Windows 上跑）
#   bash tools/build.sh android    Android .aab（传 Play）+ .apk（自己装）
#   bash tools/build.sh ios        iOS .xcarchive 之前的那一步，之后进 Xcode
#
#   加 --no-bump 用当前版本重出一次（上一次传挂了、要原号重来时用）
#   加 --set 0.7.0 顺手换 base
#
# 忘记 bump 的代价是上传被商店拒绝，而那通常发生在你已经等了二十分钟编译
# 之后 —— 所以 bump 是这个脚本的第一步，不是一条写在文档里的提醒。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TARGET="${1:-}"
shift || true

BUMP=1
SET_ARGS=()
for a in "$@"; do
  case "$a" in
    --no-bump) BUMP=0 ;;
    --set) SET_ARGS+=(--set) ;;
    *) SET_ARGS+=("$a") ;;
  esac
done

case "$TARGET" in
  mac|win|android|ios) ;;
  *) echo "用法: bash tools/build.sh mac|win|android|ios [--no-bump] [--set 0.7.0]"; exit 2 ;;
esac

# ── 1. 版本号 ──
if [ "$BUMP" = 1 ]; then
  echo "==> 版本号 +1"
  # `${a[@]+"${a[@]}"}` 这个写法是为了 macOS 自带的 bash 3.2:
  # 它在 `set -u` 下把「展开一个空数组」当成引用未定义变量，直接报错退出。
  # 新版 bash 没这个毛病，所以 `bash -n` 和 Linux 上都测不出来。
  python3 tools/bump-build.py ${SET_ARGS[@]+"${SET_ARGS[@]}"}
else
  echo "==> 不 bump，用当前版本重出"
  python3 tools/bump-build.py --sync
fi

# ── fvm ──
# tv_app 下有 .fvmrc，得用 `fvm flutter` 跑，否则用的是系统那个 flutter ——
# **两个 flutter 版本编出来的包不一样**，而且这种错不会报错，只会在某个
# 插件上莫名其妙地挂掉。哪个目录该用哪个，由那个目录里有没有 .fvmrc 决定，
# 不由记性决定。
fl() {
  if [ -f .fvmrc ] && command -v fvm >/dev/null; then
    fvm flutter "$@"
  else
    flutter "$@"
  fi
}
dt() {
  if [ -f .fvmrc ] && command -v fvm >/dev/null; then
    fvm dart "$@"
  else
    dart "$@"
  fi
}

VERSION=$(grep '^version=' VERSION | cut -d= -f2)
BUILD=$(grep '^build=' VERSION | cut -d= -f2)
DIST="$ROOT/dist"
mkdir -p "$DIST"

echo "==> TravelView $VERSION (build $BUILD) · $TARGET"

# ── 2. 编译 ──
case "$TARGET" in

mac)
  cd "$ROOT/apps/tv_desktop"
  fl build macos --release
  APP="build/macos/Build/Products/Release/tv_desktop.app"
  DMG="$DIST/TravelView-$VERSION.dmg"
  rm -f "$DMG"
  # create-dmg 没装就只留 .app —— 少一个 dmg 不该让整次构建算失败
  if command -v create-dmg >/dev/null; then
    echo "==> 打 dmg"
    create-dmg --volname "TravelView $VERSION" --window-size 520 380 \
      --icon-size 96 --app-drop-link 360 160 "$DMG" "$APP"
    echo "产物: $DMG"
  else
    echo "没装 create-dmg（brew install create-dmg），跳过打 dmg"
    echo "产物: apps/tv_desktop/$APP"
  fi
  ;;

win)
  cd "$ROOT/apps/tv_desktop"
  fl build windows --release
  echo "==> 打 msix"
  dt run msix:create
  echo "产物: apps/tv_desktop/build/windows/x64/runner/Release/（整个文件夹）"
  echo "      以及同目录下的 .msix"
  ;;

android)
  cd "$ROOT/apps/tv_app"
  # aab 传 Play，apk 自己和测试机装 —— 两个都要，别等要用时再补编一次
  fl build appbundle --release
  fl build apk --release
  cp build/app/outputs/bundle/release/app-release.aab "$DIST/TravelView-$VERSION.aab"
  cp build/app/outputs/flutter-apk/app-release.apk "$DIST/TravelView-$VERSION.apk"
  echo "产物: dist/TravelView-$VERSION.aab"
  echo "      dist/TravelView-$VERSION.apk"
  ;;

ios)
  cd "$ROOT/apps/tv_app"
  fl build ipa --release
  echo "产物: apps/tv_app/build/ios/ipa/"
  echo "没配签名的话到这一步会停在 archive —— 打开 Xcode 继续"
  ;;

esac

echo
echo "==> 完成 · TravelView $VERSION (build $BUILD)"
echo "    界面上会显示: $VERSION ($BUILD)"
