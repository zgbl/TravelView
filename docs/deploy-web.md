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

# TravelView 网站上线手册

> 目标：`https://travelview.blackrice.top` 能打开、能注册、能收钱、
> 桌面端能发布上去，拿到永久公开链接。
> 和 TensuGo 同机共存，**不动 TensuGo 的任何东西**。

---

## 0. 这台服务器上的分工

| | TensuGo | TravelView |
|---|---|---|
| 域名 | 原来那个 | `travelview.blackrice.top`（Cloudflare 橙云） |
| Node 端口 | 原来那个 | `127.0.0.1:3001` |
| 代码 | 原来那里 | `/opt/apps/travelview/` |
| 数据库 | 各自的库和用户 | 库 `travelview`，用户 `travelview` |
| 图片 | — | `/var/lib/travelview/media/` |
| nginx | 各自一个 server 块 | `/etc/nginx/sites-available/travelview` |

**数据库用户分开**，不共用 —— 出事时能隔离，将来搬走也干净。

### 照片到底在哪

| 东西 | 存在哪 | 进 Git 吗 |
|---|---|---|
| 原图 | **只在用户自己的电脑上** | 永远不会 |
| 发布用的 WebP（已剥 EXIF） | 服务器 `/var/lib/travelview/media/` | 不会 |
| 用户、订单、Story manifest | Postgres | 不会 |
| 代码 | Git 仓库 | 只有代码 |

图片现在存**服务器本地磁盘**，nginx 直接从磁盘发（`/media/`），不经过 Node。
代码里有一层存储抽象（`src/lib/storage.ts`），磁盘不够或想上 CDN 时，
改 `STORAGE_DRIVER=s3` 就能搬到 OCI Object Storage / R2，桌面端无感。

---

## 1. 先摸清现状

上去之前先看清楚，别踩到 TensuGo：

```bash
ssh -i ~/Documents/Work/OCI/Keys/ssh-key-2024-06-24-instance4-pri.key \
    ubuntu@129.80.4.27

# 资源
free -h; df -h /; nproc

# 谁在监听哪个端口（3001 必须是空的）
sudo ss -tlnp | sort -k4

# nginx 现在有哪些站
ls -l /etc/nginx/sites-enabled/; nginx -v

# Postgres 在不在、什么版本
sudo -u postgres psql -c 'select version();'
sudo -u postgres psql -c '\l'

# Node 版本（要 >= 20；没有就装 22）
node -v 2>/dev/null || echo "没装 node"

# TensuGo 装在哪，我们照着放
ls -l /opt /srv /home/ubuntu 2>/dev/null
```

Node 没装或太老：

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
```

---

## 2. 证书：Cloudflare 是橙云，别用 certbot

A 记录开了 Proxied，访客到 Cloudflare 那一段的证书由 CF 提供；
**服务器上仍然需要一张证书**给 CF 回源用。

`certbot --nginx` 在橙云下会失败（HTTP-01 验证被 CF 拦在外面）。
用 **Cloudflare Origin CA** 证书，15 年有效，只有 CF 会连它：

1. Cloudflare → SSL/TLS → Origin Server → Create Certificate
2. 主机名填 `travelview.blackrice.top`
3. 把证书和私钥存到服务器：

```bash
sudo mkdir -p /etc/ssl/travelview
sudo nano /etc/ssl/travelview/origin.pem   # 贴证书
sudo nano /etc/ssl/travelview/origin.key   # 贴私钥
sudo chmod 600 /etc/ssl/travelview/origin.key
```

4. Cloudflare → SSL/TLS → 加密模式设为 **Full (strict)**

> 模式停在 Flexible 的话，CF 会用 HTTP 回源，
> 我们的登录跳转和 Stripe 回调都会因为协议不一致而出怪问题。

---

## 3. 拉代码 + 初始化

```bash
sudo mkdir -p /opt/apps/travelview
sudo chown ubuntu:ubuntu /opt/apps/travelview
git clone <你的仓库地址> /opt/apps/travelview/src
cd /opt/apps/travelview/src

sudo bash web/deploy/setup-server.sh
```

这个脚本**可以重复跑**，做四件事：建 `travelview` 系统用户、
建目录、建数据库和数据库用户（打印出随机密码）、
生成 `/etc/travelview/env` 模板（`AUTH_SECRET` 和 `UPLOAD_SECRET` 自动填好）。

然后编辑 `/etc/travelview/env`，填三样东西：

```bash
sudo nano /etc/travelview/env
```

| 变量 | 填什么 |
|---|---|
| `DATABASE_URL` | 把脚本打印的数据库密码填进去 |
| `STRIPE_SECRET_KEY` | 先用 `sk_test_...` 跑通 |
| `STRIPE_PRICE_ONETIME` | Stripe 后台建一个「单篇发布」价格，复制 `price_...` |

`STRIPE_WEBHOOK_SECRET` 等第 6 节配完 webhook 再回来填。

建表：

```bash
set -a; . /etc/travelview/env; set +a
psql "$DATABASE_URL" -f /opt/apps/travelview/src/web/db/schema.sql
```

---

## 4. 上线

```bash
sudo cp /opt/apps/travelview/src/web/deploy/travelview-web.service \
        /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable travelview-web

cd /opt/apps/travelview/src
sudo bash web/deploy/release.sh
```

`release.sh` 也是**可以重复跑**的：它先完整构建到一个带时间戳的新目录，
最后一步才切 `current` 软链并重启。构建挂了线上还是旧版本，一点没动。
出问题回滚就是把软链指回上一个版本再 `systemctl restart`。

nginx：

```bash
sudo cp /opt/apps/travelview/src/web/deploy/nginx-travelview.conf \
        /etc/nginx/sites-available/travelview
sudo ln -s /etc/nginx/sites-available/travelview /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

`nginx -t` 一定要过再 reload —— 配置有错直接 reload 会**连 TensuGo 一起挂**。

---

## 5. 冒烟测试（按顺序，一步不过就停）

1. `curl -I https://travelview.blackrice.top` 返回 200
2. 浏览器打开，落地页出来
3. 注册账号，能登录
4. `/pricing` 付款，测试卡 `4242 4242 4242 4242`，任意未来日期 + 任意 CVC
5. `/account` 看到额度到账（**没到账就是 webhook 没通，看第 6 节**）
6. `/account` 生成发布令牌
7. 桌面端「生成旅行回顾」→ 导出 → 发布，域名填 `https://travelview.blackrice.top`
8. 打开返回的公开链接 —— 照片、地图、路线、文字都在
9. 服务器上 `ls /var/lib/travelview/media/s/` —— 图片确实落盘了

---

## 6. Stripe Webhook

**权益只在 webhook 里发放**，这步不通，用户付了钱也拿不到额度。

1. Stripe → Developers → Webhooks → Add endpoint
2. 地址 `https://travelview.blackrice.top/api/stripe/webhook`
3. 事件：`checkout.session.completed`、`customer.subscription.updated`、
   `customer.subscription.deleted`
4. 把 `whsec_...` 填进 `/etc/travelview/env`，然后
   `sudo systemctl restart travelview-web`
5. Stripe 后台点 "Send test webhook"，确认返回 200

---

## 7. 分享到 Facebook

公开链接粘进去，卡片必须有大图和标题。不对就用
[Facebook 分享调试器](https://developers.facebook.com/tools/debug/)
点 "Scrape Again" —— 它缓存得很凶。OG 图必须是 PNG，不能是 WebP
（我们已经用 `next/og` 动态生成 PNG）。

---

## 8. 两个欠账

### 8.1 备份

**自托管没人替你做这件事**，而且没恢复过的备份不算备份。

```bash
# /etc/cron.daily/travelview-backup
set -a; . /etc/travelview/env; set +a
pg_dump "$DATABASE_URL" | gzip > /var/backups/tv-$(date +%F).sql.gz
tar czf /var/backups/tv-media-$(date +%F).tgz -C /var/lib/travelview media
find /var/backups -name 'tv-*' -mtime +30 -delete
```

图片同样要备份 —— 用户发布的 Story 丢了**没法从原图重建**
（原图在他自己电脑上，我们连有哪些都不知道）。

### 8.2 地图瓦片

现在指着 `tile.openstreetmap.org`，那是给开发和小流量用的公益服务，
正式流量会违反它的使用政策，也把访客的浏览行踪送给了第三方。
上线前换成自托管 Protomaps，见 `Design/map-tiles.md`。

---

## 9. 出问题先看哪里

| 现象 | 多半是 |
|---|---|
| 502 Bad Gateway | Node 没起来：`journalctl -u travelview-web -n 50` |
| 521 / 526（Cloudflare 报错页） | 源站证书不对，或 CF 加密模式不是 Full (strict) |
| 页面能开，登录报错 | `AUTH_SECRET` / `AUTH_URL` 没填或填错 |
| 付了钱额度不加 | webhook 没配、密钥不对，或反代改写了 body |
| 发布时上传 413 | nginx 少了 `client_max_body_size 12m` |
| 发布返回 403 上传票据无效 | 服务器时间不对，或改过 `UPLOAD_SECRET` 没重启 |
| 发布返回 401 | 令牌被吊销，去 `/account` 重新生成 |
| 发布返回 402 | 额度用完 —— 这是正常行为，不是故障 |
| Story 文字在、图片全裂 | nginx `/media/` 那段没配，或 `NEXT_PUBLIC_MEDIA_BASE` 不对 |
| 改了 `NEXT_PUBLIC_*` 不生效 | 它们编译进前端代码，必须重跑 `release.sh` |

---

## 10. 一页纸清单

```text
[ ] 摸清现状: 端口 3001 空着、Postgres 在、Node >= 20
[ ] Cloudflare Origin 证书 + 加密模式 Full (strict)
[ ] git clone 到 /opt/apps/travelview/src
[ ] sudo bash web/deploy/setup-server.sh
[ ] 编辑 /etc/travelview/env（数据库密码 + Stripe）
[ ] psql -f web/db/schema.sql 建表
[ ] 装 systemd unit + release.sh
[ ] nginx 配置 + nginx -t + reload
[ ] 注册 -> 付款 -> 额度到账
[ ] 发布令牌 -> 桌面端发布 -> 公开链接能打开
[ ] Stripe webhook -> 重启 -> 测试事件 200
[ ] FB 分享调试器看卡片
[ ] 备份 cron
[ ] 换掉地图瓦片
```
