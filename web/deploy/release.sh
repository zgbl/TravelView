#!/usr/bin/env bash
# 构建并发布一个新版本。**可以重复跑**，失败不会影响正在跑的版本。
#
#   cd /opt/travelview/src && git pull && sudo bash web/deploy/release.sh
#
# 用「目录 + current 软链」的方式发布: 新版本先完整构建好，
# 最后一步才切软链 + 重启。构建挂了，线上还是旧版本，一点没动。
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # .../web
APP_ROOT=/opt/travelview/web
ENV_FILE=/etc/travelview/env
STAMP=$(date +%Y%m%d-%H%M%S)
DEST="$APP_ROOT/releases/$STAMP"

set -a; . "$ENV_FILE"; set +a

echo "==> 自检环境变量"
node "$SRC_DIR/scripts/preflight.mjs"

echo "==> 安装依赖"
cd "$SRC_DIR"
npm ci 2>/dev/null || npm install

echo "==> 构建"
# NEXT_PUBLIC_* 会被编译进前端代码，所以必须在构建时就在环境里
npm run build

echo "==> 组装 $DEST"
mkdir -p "$DEST"
cp -r .next/standalone/. "$DEST"/
mkdir -p "$DEST/.next"
cp -r .next/static "$DEST/.next/static"
[ -d public ] && cp -r public "$DEST/public"
chown -R travelview:travelview "$DEST"

echo "==> 切换 current 并重启"
ln -sfn "$DEST" "$APP_ROOT/current"
systemctl restart travelview-web

sleep 2
systemctl is-active --quiet travelview-web && echo "    服务已启动" || {
  echo "    启动失败，最近日志:"; journalctl -u travelview-web -n 30 --no-pager
  exit 1
}

echo "==> 只保留最近 5 个版本"
ls -1dt "$APP_ROOT"/releases/* | tail -n +6 | xargs -r rm -rf

echo
curl -sS -o /dev/null -w "本机自测 HTTP %{http_code}\n" http://127.0.0.1:3001/
echo "完成: $STAMP"
