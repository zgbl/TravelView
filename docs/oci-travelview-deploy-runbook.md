# TravelView OCI 实际部署记录 / Runbook

> 这是 2026-09-05/06 在 OCI 生产机 **129.80.4.27**（Ubuntu 24.04 aarch64）上把
> TravelView 与 TensuGo 同机部署的**实际经过记录**。通用部署方法看
> `docs/deploy-web.md` 与 `web/deploy/*.sh`；本文记的是"这台机器上到底装成了什么样、
> 关键信息放哪、下一步还欠什么"。

---

## 1. 一句话状态

- ✅ 代码、数据库、Web 服务都已就位并验证（注册 / 发布 / 上传 / 额度 / 公开页全链路 200）。
- ✅ **已对外公开**（2026-09-06）：Cloudflare Origin CA 证书已就位，nginx 站点已启用，`https://travelview.blackrice.top` 返回 200。
- ⛔ **还差收款**：Stripe 仍是占位符，需要你填真实密钥后才能真正收钱（见 §4.2）。

---

## 2. 关键信息速查（一定要记住）

| 项 | 值 / 位置 |
|---|---|
| 服务器 | `ubuntu@129.80.4.27`（OCI，Ubuntu 24.04 aarch64，TensuGo 同机） |
| SSH 私钥 | `/Users/tuxy/Documents/Work/OCI/Keys/ssh-key-2024-06-24-instance4-pri.key` |
| 代码目录 | `/opt/travelview/src`（来自 GitHub `zgbl/TravelView`，HEAD `cfcbb9e`） |
| 发布根 | `/opt/travelview/web`（`releases/<时间戳>/` + `current` → 软链到最新） |
| systemd 服务 | `travelview-web`（Next.js standalone，端口 **127.0.0.1:3001**） |
| 运行用户 | 系统用户 `travelview` |
| 数据库 | Postgres 库 `travelview`，角色 `travelview`（**与 TensuGo 的库/用户完全分开**） |
| 数据库连接串 | 在 `/etc/travelview/env` 的 `DATABASE_URL`（含真实密码，别外泄） |
| 环境变量文件 | `/etc/travelview/env`（0600，root；AUTH_SECRET/UPLOAD_SECRET 已自动生成） |
| 发布图片目录 | `/var/lib/travelview/media/`（nginx 从磁盘直发，不经过 Node） |
| nginx 站点文件 | `/etc/nginx/sites-available/travelview`（**已放好、尚未 enable**） |
| 证书目录 | `/etc/ssl/travelview/`（**目前是空的**，等 Cloudflare Origin CA 证书） |
| 备份 | `/etc/cron.daily/travelview-backup` → `/var/backups/tv-*.sql.gz / tv-media-*.tgz`，保留 30 天 |
| 域名 | `travelview.blackrice.top`（Cloudflare A 记录 **Proxied/橙云** → 129.80.4.27） |

---

## 3. 部署经过（踩过的坑都标出来）

1. **摸清现状**（只读）：确认 3001 空闲、Postgres 只有 `tensugo` 库、Node 已是 v24、
   TensuGo 在 `/opt/tensugo*`、nginx 只用 Let's Encrypt 服务 `tensugo.com` 反代 3217。
2. **源码**：发现 `web/`（真正要部署的 Next.js 应用）**当时没进 git**。你 commit + push 到
   GitHub 后，服务器统一从 GitHub 拉取：`git clone … /opt/travelview/src`。
3. **修一个构建 bug**：`web/src/lib/stripe.ts` 写死了 `apiVersion: '2024-12-18.acacia'`，
   与当前 stripe SDK 的类型（`'2025-02-24.acacia'`）冲突，`next build` 类型检查直接挂。
   改成不锁版本（缺省用 SDK 默认）→ 已随你那次 GitHub commit 上去。
4. **路径调整**：部署脚本默认 `/opt/apps/travelview`；因为 TensuGo 在 `/opt/tensugo`，
   你希望两者并列便于查找，所以实际落到 **`/opt/travelview`**，并把
   `web/deploy/{setup-server.sh,release.sh,travelview-web.service}` 里的
   `/opt/apps/travelview` 全部替换为 `/opt/travelview`（该改动已在 GitHub 上）。
5. **初始化**：`sudo bash web/deploy/setup-server.sh` → 建系统用户、建 `travelview`
   数据库+用户、生成 `/etc/travelview/env`。
6. **建表**：`psql "$DATABASE_URL" -f db/schema.sql` → `users / publish_tokens / stories / payments`。
7. **上线**：装 `travelview-web.service` → `release.sh`（npm install + next build →
   组装到带时间戳目录 → 切 `current` 软链 → systemctl restart）。
8. **验证**（全是真实接口，已测通）：
   - 注册 `POST /api/signup` → 200，DB 有行
   - 发布 `POST /api/publish`（带 publish token）→ 200，返回 `slug` + 预签名上传票据
   - 上传 `PUT /api/upload?key=…&exp=…&sig=…` → 200，WebP 落到 `/var/lib/travelview/media/s/<slug>/…`
   - 额度 `story_credits` 1→0 扣减正确
   - 公开页 `GET /s/<slug>` → 200，正常出标题
   - 测试数据随后已清空。
9. **备份**：装 `/etc/cron.daily/travelview-backup` 并跑过一次（初始备份已生成）。
10. **nginx**：站点配置已复制到 `/etc/nginx/sites-available/travelview`，**故意不 enable、
    不 reload**（还没证书，硬上会让 `nginx -t` 挂，连带 TensuGo）。

---

## 4. 还没做完的（阻塞项，需要你的账号操作）

外部开服需要两张凭证，都是**只有你能弄**的东西：

### 4.1 TLS（二选一）
- **路线 A（保留橙云）**：Cloudflare → SSL/TLS → Origin Server → *Create Certificate*，
  主机名 `travelview.blackrice.top`；并把 SSL 加密模式设为 **Full (strict)**。
  把证书/私钥贴到服务器：`/etc/ssl/travelview/origin.pem` / `origin.key`（key 记得 `chmod 600`）。
- **路线 B（最省事，跟 TensuGo 一样）**：把该 A 记录从 Proxied 改为 **DNS-only（灰云）**，
  然后我在这台机上跑 `certbot` 即可，不需要你贴任何证书。

### 4.2 Stripe（两条路线都需要）
把 `/etc/travelview/env` 里这几个占位符换成真实值，然后 `sudo systemctl restart travelview-web`：
`STRIPE_SECRET_KEY`（sk_test_… 或 sk_live_…）、`STRIPE_PRICE_ONETIME`（price_…）、
可选 `STRIPE_PRICE_SUBSCRIPTION`；webhook 地址填 `https://travelview.blackrice.top/api/stripe/webhook`
（事件：checkout.session.completed / customer.subscription.updated / customer.subscription.deleted），
拿到 `whsec_…` 填 `STRIPE_WEBHOOK_SECRET`。

> ⚠️ 现在的 env 里 Stripe 还是占位符，**没有真实支付能力**；`NEXT_PUBLIC_MAP_TILES`
> 也还指向公共 OSM（正式流量前要换成自托管，见 `Design/map-tiles.md`）。

### 4.3 证书就位后的收尾命令（届时我来执行）
```bash
# 1) 把 nginx 站点启用并 reload（先 nginx -t，必须过）
sudo ln -s /etc/nginx/sites-available/travelview /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# 2) 冒烟：curl -I https://travelview.blackrice.top 应 200；注册→付款→发布→公开页
# 3) 若走路线 A，记得 CF SSL 模式 = Full (strict)
```

---

## 5. 日常运维速查

```bash
# 状态
systemctl status travelview-web --no-pager
sudo journalctl -u travelview-web -n 50
sudo ss -tlnp | grep 3001

# 重新部署（从 GitHub 拉最新并零停机上线，保留最近 5 版）
cd /opt/travelview/src && git pull && sudo bash web/deploy/release.sh

# 回滚：把 current 软链指回上一个版本再重启
sudo ls -1t /opt/travelview/web/releases
sudo ln -sfn /opt/travelview/web/releases/<上一版时间戳> /opt/travelview/web/current
sudo systemctl restart travelview-web

# 手动备份（一般不用，cron 每天跑）
sudo bash /etc/cron.daily/travelview-backup
```

---

## 6. 常见现象排查（扩展自 deploy-web.md）

| 现象 | 多半是 |
|---|---|
| 502 Bad Gateway | Node 没起来：`journalctl -u travelview-web -n 50` |
| 521 / 526（CF 报错页） | 源站证书不对 / CF 模式不是 Full (strict) |
| 能开但登录报错 | `AUTH_SECRET` / `AUTH_URL` 没填对 |
| 付了钱额度不加 | webhook 没配 / 密钥错 / 反代改写 body（见 nginx `proxy_request_buffering off`） |
| 发布上传 413 | nginx 少了 `client_max_body_size 12m` |
| 发布 403 票据无效 | 服务器时间不对 / 改过 UPLOAD_SECRET 没重启 |
| 发布 401 | 令牌被吊销 → /account 重新生成 |
| 发布 402 | 额度用完（正常业务，不是故障） |
| 文字在、图片全裂 | nginx /media/ 段没配 / NEXT_PUBLIC_MEDIA_BASE 不对 |
| 改了 NEXT_PUBLIC_* 不生效 | 它编译进前端，必须重跑 release.sh |

---

## 7. 一个容易误会的点（DNS）

`ping travelview.blackrice.top` 显示 `104.21.x / 172.67.x` **是正常的**：A 记录开了
Proxied（橙云），公网只见 Cloudflare 边缘 IP，看不到源站 129.80.4.27。源站在 Cloudflare
眼里才是真实 IP。


---

## 8. 上线补记（2026-09-06）

- **证书**：你已在 `/etc/ssl/travelview/origin.pem` + `origin.key` 放入 Cloudflare Origin CA
  证书（CN=CloudFlare Origin Certificate，有效期 2026-09-06 ~ 2041-09-02，私钥 600，与证书匹配）。
- **nginx 已启用**：`ln -s sites-available/travelview sites-enabled/` → `nginx -t` → `reload`。
- **踩坑**：这台 Ubuntu 的 **nginx 1.24 不支持**独立的 `http2 on;` 指令，`nginx -t` 会报
  `unknown directive "http2"`。已把配置改成 `listen 443 ssl http2;`（同时修正了
  `web/deploy/nginx-travelview.conf` 仓库源文件 + 服务器 `/opt/travelview/src` 副本，
  **记得把这个改动 commit 上 GitHub**，否则下次从 git 拉取重部署会再踩）。
- **验证（通过 Cloudflare 公网）**：
  - `https://travelview.blackrice.top/` → **200**，出 TravelView 主页
  - `http://…` → 301 → `https://…`
  - 本机回源 `https`（Host: travelview.blackrice.top）→ 200；`/media/…` → 200
  - TensuGo（`https://tensugo.com`）→ 200，未受影响
- **提醒**：Cloudflare SSL 模式需为 **Full (strict)**（当前公网 200 说明已生效）。
- **还欠**：真实 Stripe 密钥（§4.2）；地图瓦片仍指向公共 OSM（见 `Design/map-tiles.md`）。

