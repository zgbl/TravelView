#!/usr/bin/env bash
# 服务器一次性初始化。**可以重复跑**，已经存在的东西会跳过。
#
#   sudo bash deploy/setup-server.sh
#
# 干三件事: 建目录和系统用户、建数据库、放好 /etc/travelview/env 模板。
# 不碰 TensuGo 的任何东西。
set -euo pipefail

APP_ROOT=/opt/travelview
MEDIA_ROOT=/var/lib/travelview/media
ENV_FILE=/etc/travelview/env
DB_NAME=travelview
DB_USER=travelview

echo "==> 系统用户"
id -u travelview >/dev/null 2>&1 || \
  useradd --system --home-dir "$APP_ROOT" --shell /usr/sbin/nologin travelview

echo "==> 目录"
mkdir -p "$APP_ROOT/web/releases" "$MEDIA_ROOT" /etc/travelview /etc/ssl/travelview
chown -R travelview:travelview "$APP_ROOT" /var/lib/travelview
chmod 750 /etc/travelview

echo "==> 数据库"
if sudo -u postgres psql -tAc \
     "select 1 from pg_roles where rolname='$DB_USER'" | grep -q 1; then
  echo "    用户 $DB_USER 已存在，跳过"
else
  DB_PASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)
  sudo -u postgres psql -c \
    "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
  echo "    数据库密码: $DB_PASS"
  echo "    ↑ 记下来，等下要填进 $ENV_FILE"
fi
sudo -u postgres psql -tAc \
  "select 1 from pg_database where datname='$DB_NAME'" | grep -q 1 || \
  sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"

echo "==> 环境变量模板"
if [ ! -f "$ENV_FILE" ]; then
  cat > "$ENV_FILE" <<'ENV'
TRAVELVIEW_DATABASE_URL=postgres://travelview:换成上面那个密码@127.0.0.1:5432/travelview
AUTH_SECRET=
# 老域名 travelview.blackrice.top 也直接服务（不跳转），所以不用 AUTH_URL 钉死一个域，
# 改成信任请求头里的 host，两个域名各自登录各自生效。
AUTH_TRUST_HOST=true

STORAGE_DRIVER=local
MEDIA_ROOT=/var/lib/travelview/media
UPLOAD_SECRET=

STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
STRIPE_PAYMENT_METHODS=
STRIPE_PRICE_PRO_YEARLY=
STRIPE_PRICE_PRO_MONTHLY=
STRIPE_PRICE_CREDITS_5=
STRIPE_PRICE_CREDITS_10=
STRIPE_PRICE_CREDITS_25=

NEXT_PUBLIC_SITE_URL=https://yourtravelview.com
NEXT_PUBLIC_MEDIA_BASE=https://yourtravelview.com/media
NEXT_PUBLIC_MAP_TILES=
ENV
  sed -i "s|^AUTH_SECRET=$|AUTH_SECRET=$(openssl rand -base64 32)|" "$ENV_FILE"
  sed -i "s|^UPLOAD_SECRET=$|UPLOAD_SECRET=$(openssl rand -base64 32)|" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "    已生成 $ENV_FILE（AUTH_SECRET / UPLOAD_SECRET 已自动填好）"
else
  echo "    $ENV_FILE 已存在，没有覆盖"
fi

echo
echo "接下来:"
echo "  1. 编辑 $ENV_FILE，填数据库密码和 Stripe 三个值"
echo "  2. psql \"\$TRAVELVIEW_DATABASE_URL\" -f web/db/schema.sql   建表"
echo "  3. bash deploy/release.sh                        构建并上线"
