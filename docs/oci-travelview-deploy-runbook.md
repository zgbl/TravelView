# TravelView OCI 实际部署记录 / Runbook

> 这是 2026-09-05/06 在 OCI 生产机 **129.80.4.27**（Ubuntu 24.04 aarch64）上把
> TravelView 与 TensuGo 同机部署的**实际经过记录**。通用部署方法看
> `docs/deploy-web.md` 与 `web/deploy/*.sh`；本文记的是"这台机器上到底装成了什么样、
> 关键信息放哪、下一步还欠什么"。

---

## 1. 一句话状态

- ✅ 代码、数据库、Web 服务都已就位并验证（注册 / 发布 / 上传 / 额度 / 公开页全链路 200）。
- ✅ **已对外公开**（2026-09-06）：Cloudflare Origin CA 证书已就位，nginx 站点已启用，`https://travelview.blackrice.top` 返回 200。
- ✅ **换到正式域名 yourtravelview.com**（2026-09-12）：新老域名各用一张 Origin CA 证书
  （SNI 决定，切了 CF **Full (strict)** 后复验全绿，无 526）；`www` 301 到裸域；
  老域名内容照常服务。经过与结论见 §6.5。
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
| 数据库连接串 | 在 `/etc/travelview/env` 的 `TRAVELVIEW_DATABASE_URL`（含真实密码，别外泄） |
| 环境变量文件 | `/etc/travelview/env`（0600，root；AUTH_SECRET/UPLOAD_SECRET 已自动生成） |
| 发布图片目录 | `/var/lib/travelview/media/`（nginx 从磁盘直发，不经过 Node） |
| nginx 站点文件 | `/etc/nginx/sites-available/travelview`（已 enable 并 reload） |
| 证书 | **两对，各自独立**：`yourtravelview_origin.pem/.key`（`*.yourtravelview.com` + `yourtravelview.com`）与 `origin.pem/.key`（`*.blackrice.top`，老的那对别动）；由 SNI 决定用哪张 |
| nginx 应用片段 | `/etc/nginx/snippets/travelview-app.conf`（站点文件里两个 443 块 include 它，改完要两个一起同步） |
| 备份 | `/etc/cron.daily/travelview-backup` → `/var/backups/tv-*.sql.gz / tv-media-*.tgz`，保留 30 天 |
| 正式域名 | `yourtravelview.com`（Cloudflare 橙云 → 129.80.4.27；`www` 301 到裸域） |
| 老域名 | `travelview.blackrice.top`（**继续直接服务、不跳转**，只是账号类页面 301 到正式域名） |
| 演示站 | `demo.yourtravelview.com`（**灰云 DNS-only → 另一台实例 `193.122.150.15`，不在生产机上**；证书与配置见 §9） |
| 环境变量 | `AUTH_URL=https://yourtravelview.com` + `NEXT_PUBLIC_SITE_URL/MEDIA_BASE` 同域（见 §6.5） |

---

## 3. 部署经过（踩过的坑都标出来）

1. **摸清现状**（只读）：确认 3001 空闲、Postgres 只有 `tensugo` 库、Node 已是 v24、
   TensuGo 在 `/opt/tensugo*`、nginx 只用 Let's Encrypt 服务 `tensugo.com` 反代 3217。
2. **源码**：发现 `web/`（真正要部署的 Next.js 应用）**当时没进 git**。你 commit + push 到
   GitHub 后，服务器统一从 GitHub 拉取：`git clone … /opt/travelview/src`。
3. **修一个构建 bug**：`web/src/lib/stripe.ts` 写死了 `apiVersion: '2024-12-18.acacia'`，
   与当前 stripe SDK 的类型（`'2025-02-24.acacia'`）冲突，`next build` 类型检查直接挂。
   改成不锁版本（缺省用 SDK 默认）→ 已随你那次 GitHub commit 上去。
4. **路径调整**：部署脚本默认 `/opt/travelview`；因为 TensuGo 在 `/opt/tensugo`，
   你希望两者并列便于查找，所以实际落到 **`/opt/travelview`**，并把
   `web/deploy/{setup-server.sh,release.sh,travelview-web.service}` 里的
   `/opt/travelview` 全部替换为 `/opt/travelview`（该改动已在 GitHub 上）。
5. **初始化**：`sudo bash web/deploy/setup-server.sh` → 建系统用户、建 `travelview`
   数据库+用户、生成 `/etc/travelview/env`。
6. **建表**：`psql "$TRAVELVIEW_DATABASE_URL" -f db/schema.sql` → `users / publish_tokens / stories / payments`。
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
把 `/etc/travelview/env` 里的 Stripe 段换成真实值，然后 `sudo systemctl restart travelview-web`：
`STRIPE_SECRET_KEY`（sk_test_… 或 sk_live_…），加 5 条 price ID ——
`STRIPE_PRICE_PRO_YEARLY`（$50/年）、`STRIPE_PRICE_PRO_MONTHLY`（$8/月）、
`STRIPE_PRICE_CREDITS_5`（$5=2 篇）、`STRIPE_PRICE_CREDITS_10`（$10=5 篇）、
`STRIPE_PRICE_CREDITS_25`（$25=15 篇）。测试和正式是两套完全不同的 ID，
**切换只改这一段，代码一行不动**（模式由密钥前缀 `sk_test_` / `sk_live_` 决定）。

webhook 地址填 `https://yourtravelview.com/api/stripe/webhook`

> ⚠ **必须用裸域，不要填 `www.yourtravelview.com`。**
> nginx 把 www 301 到裸域，而 **Stripe 不跟随跳转**，3xx 一律算投递失败 ——
> 填 www 的结果是每一笔付款的 webhook 都到不了，额度一条都发不出去。

事件勾这 5 个，少一个就会出事：

| 事件 | 漏了会怎样 |
|---|---|
| `checkout.session.completed` | 付了钱不发额度 |
| `customer.subscription.created` / `.updated` | 续费后 `subscription_until` 不更新 → 续了费的人到期反而失去权限 |
| `customer.subscription.deleted` | 退订后状态还留在 `active` |
| `invoice.payment_failed` | 卡过期了不知道，不会标 `past_due` |

拿到 `whsec_…` 填 `STRIPE_WEBHOOK_SECRET`。

> **注意** 截至 2026-09-22，env 里是 **test 模式**的真实密钥 + 5 条 test price，
> live 配置还没有；`NEXT_PUBLIC_MAP_TILES`
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
| 页面说"网络不通"，但 nginx 日志里明明是 502 | **Cloudflare 把源站 502/504 的响应体换成了它自己的 `error code: 502`**，前端的 `res.json()` 解析失败，只能退化成"网络不通"。实测 500/503/429 的响应体是原样透传的 —— 所以**业务错误别用 502/504 表达**，用 503（发信失败就是这么改的）。 |
| 文字在、图片全裂 | nginx /media/ 段没配 / NEXT_PUBLIC_MEDIA_BASE 不对 |
| 改了 NEXT_PUBLIC_* 不生效 | 它编译进前端，必须重跑 release.sh |
| **演示站**地址栏 "Not Secure" / DevTools "broken HTTPS" + "active content with certificate errors" | 演示站是灰云，证书得由演示机自己出。多半是 `demo.yourtravelview.com` 的 Let's Encrypt 证书缺失或名字不匹配，nginx 对该 SNI 回落到了默认 server 块的证书（见 §9）。**把生产机那套 Cloudflare Origin CA 证书搬过去没用** —— 浏览器不认 Origin CA。 |

---

## 6.5 换域名那次踩的坑（2026-09-12，务必先读）

给站点加新域名时，下面这条最容易白折腾半天：

**Next.js 15.5 的 standalone server 会忽略 `Host` / `X-Forwarded-Host`**，
一律按 `HOSTNAME:PORT`（也就是 `0.0.0.0:3001`）拼绝对地址。
后果是登录跳转把浏览器甩到 `https://0.0.0.0:3001/login`。

- `next.config.mjs` 里写 `experimental.trustHostHeader: true` **没用**：
  Next 15.5 已经不认这个键，构建时警告 `Unrecognized key(s) ... 'trustHostHeader'`，
  值被丢掉（可以在构建产物 `server.js` 的 `nextConfig` 里看到仍是 `false`）。
- 手工把构建产物里的 `"trustHostHeader":false` 改成 `true` **更糟**：
  中间件的语言跳转也会变成 `https://0.0.0.0:3001/zh`。
- **正确做法**：不碰 Next，改为在服务器上把 `AUTH_URL` 钉成正式域名。
  代价是 Auth.js 只认这一个域：在老域名上登录会被跳到正式域名。

结论：**多域名服务时，账号/登录归正式域名，老域名只负责"内容还打得开"。**
nginx 里把老域名的 `/login /signup /account /admin /stories /link` 301 到正式域名，
避免"在老域名上登了、被跳走、看着像没登"。

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

---

## 9. 演示站 `demo.yourtravelview.com`（独立实例，2026-09-26 补记）

### 9.1 它和主站不是一台机器

这是本节最要紧的一条，**别把两边的 nginx 配置互相抄**：

| | 正式站 | 演示站 |
|---|---|---|
| 域名 | `yourtravelview.com` | `demo.yourtravelview.com` |
| DNS | Cloudflare **Proxied（橙云）** | **DNS-only（灰云）** |
| 解析到 | `129.80.4.27`（生产机） | **`193.122.150.15`（另一台 OCI 实例）** |
| 访客看到的证书 | Cloudflare 边缘证书 | **演示机自己的 Let's Encrypt** |
| 源站证书 | Cloudflare **Origin CA**（`/etc/ssl/travelview/yourtravelview_origin.pem`） | **Let's Encrypt**（`/etc/letsencrypt/live/demo.yourtravelview.com/`） |
| nginx 配置 | `/etc/nginx/sites-available/travelview` | `/etc/nginx/sites-available/demo.yourtravelview.com`（仓库源文件 `web/deploy/nginx-travelview-demo.conf`） |
| SSH | `ubuntu@129.80.4.27`（`~/Documents/Work/OCI/Keys/` 下的私钥） | `ubuntu@193.122.150.15`（`~/Documents/JH/2026/Cloudflare/OCI-Key/ssh-key-2026-09-25.key`） |

> 生产机 `129.80.4.27` 上**没有、也不该有** demo 的 server 块
> （2026-09-26 用 `sudo nginx -T | grep server_name` 确认过，只有 tensugo / forum /
> yourtravelview / www / blackrice 这些）。

### 9.2 2026-09-26 那次 broken HTTPS 的根因

现象（用户截图）：

- Chrome 地址栏 `Not Secure`
- DevTools → Security：`This page isn't secure (broken HTTPS).`
  → Resources：`active content with certificate errors`
  → `You have recently allowed content loaded with certificate errors (such as scripts or iframes) to run on this site.`

根因：**演示站当时没有属于自己的证书**。演示站是灰云，浏览器直连 `193.122.150.15`；
该 SNI 在演示机上匹配不到带证书的 server 块，nginx 回落到当时唯一可用的 443
server 块的证书，名字和 `demo.yourtravelview.com` 对不上 → 整页证书校验失败。
用户点了"继续访问"后，同一连接上加载的脚本/iframe 就都记成"certificate errors"
的 active content。

**为什么主站没事**：主站走 Cloudflare 橙云，访客那一段的证书由 CF 边缘提供，
源站用不用 Origin CA 浏览器根本看不到。演示站是灰云，这套就完全不适用 ——
**Origin CA 证书只有 Cloudflare 认，浏览器不认**，照抄主站必然翻车。

当天 `02:19:36 UTC` 签发 `demo.yourtravelview.com` 的 Let's Encrypt 证书后恢复正常。

### 9.3 复验（2026-09-26，公网 + 登机双重复核，全绿）

公网侧与登录后两侧都核过：`nginx -t` 通过；`/etc/nginx/sites-available/demo.yourtravelview.com`
与仓库 `web/deploy/nginx-travelview-demo.conf` **非注释部分 47/47 行一致**。

```bash
# 证书名字、签发者、有效期  →  CN=demo.yourtravelview.com / issuer=Let's Encrypt / Verify 0
echo | openssl s_client -connect demo.yourtravelview.com:443 \
      -servername demo.yourtravelview.com 2>/dev/null | \
      openssl x509 -noout -subject -issuer -dates

# 跳转与响应
curl -sSI http://demo.yourtravelview.com/en    | head -1   # 301 → https
curl -sSI https://demo.yourtravelview.com/en   | head -1   # 200
```

实测结果：A 记录唯一（`193.122.150.15`，无 AAAA、无 CNAME）；证书
`notBefore=Sep 26 02:19:36 2026` / `notAfter=Dec 25 02:19:35 2026`；
链路 leaf → YE1 → Root YE → ISRG Root X2，TLS 1.2 与 1.3 均 `Verify return code: 0`；
`http` → `301 https`；`/en` → `HTTP/2 200`；`/media/**` 与 `/_next/static/**`
由 nginx 直发（`cache-control: public, max-age=31536000, immutable`）。

> 附注：演示站 `/robots.txt` 返回 Next 的 404 页，而主站返回一份"内容信号"策略文本 ——
> 这**不是**演示站版本旧。那份 robots.txt 是 **Cloudflare 注入**的
> （响应头 `server: cloudflare` + `cf-cache-status: BYPASS`），灰云站自然没有。

### 9.4 这台机器长什么样（2026-09-26 登录实测）

SSH：`ssh -i /Users/tuxy/Documents/JH/2026/Cloudflare/OCI-Key/ssh-key-2026-09-25.key ubuntu@193.122.150.15`
（**不是** `~/Documents/Work/OCI/Keys/` 里那些 —— 那批私钥在这台机器上全部被拒。）

| 项 | 值 |
|---|---|
| hostname | `instance-20260925-cf-demo`（Ubuntu 24.04 aarch64） |
| 代码 | `/opt/TravelView`（ubuntu 用户克隆，HEAD `467b0f5`，与仓库 main 同点） |
| 发布根 | `/opt/travelview/web/releases/<时间戳>` + `current` 软链 |
| systemd | `travelview-web.service`（跑在 `0.0.0.0:3001`，与生产机同款 unit，含 `ProtectSystem=strict` + `ReadWritePaths`） |
| env | `/etc/travelview/env`，`AUTH_URL` / `NEXT_PUBLIC_SITE_URL` / `NEXT_PUBLIC_MEDIA_BASE` **都指向 `demo.yourtravelview.com`**（自洽，链接不会跑回主站） |
| nginx 站点 | `/etc/nginx/sites-available/demo.yourtravelview.com`（79 行，**把反代与 /media 段落内联写全**，不用 snippet） |
| 上游 | 文件里 `upstream travelview_app { server 127.0.0.1:3001; }` —— 改端口只改这一处 |
| 证书 | `/etc/letsencrypt/live/demo.yourtravelview.com/`，ECDSA，`notAfter=2026-12-25 02:19:35 UTC` |
| 续期 | certbot 2.9.0，`authenticator = webroot`，`webroot_path = /var/www/certbot`；`certbot.timer` **在跑**；已装 deploy hook 在续期后 `systemctl reload nginx`（见 §9.5） |

**仓库源文件**：`web/deploy/nginx-travelview-demo.conf` —— 已与线上文件**逐行比对，
非注释部分 47/47 行完全一致**，并在本机 `nginx -t` 通过（用桩证书/桩路径验证）。
改仓库那份之后，记得同步回这台机器再 `nginx -t && systemctl reload nginx`。

> ⚠ 别往这台机器上抄生产机的配置写法：这里**没有**
> `/etc/nginx/snippets/travelview-app.conf`（只有 Ubuntu 自带的
> `fastcgi-php.conf` / `snakeoil.conf`）。写成生产机那种
> `include /etc/nginx/snippets/travelview-app.conf` 会让 `nginx -t` 直接失败。

### 9.5 续期后必须 reload nginx —— **已修复**（2026-09-26）

**背景（曾经是下一次 broken HTTPS 的种子）：**

`certbot renew --dry-run` 实测通过：

```
Congratulations, all simulated renewals succeeded:
  /etc/letsencrypt/live/demo.yourtravelview.com/fullchain.pem (success)
no renewal failures
```

**但续期成功并不等于站点用上新证书。** nginx 只在启动/reload 时把证书读进内存，
之后**不会**因为磁盘上的文件变了就自动重读。而这台机器上原本：

- `/etc/letsencrypt/renewal/demo.yourtravelview.com.conf` 里**没有** `renew_hook`
- `/etc/letsencrypt/renewal-hooks/deploy/`（以及 pre/post）**三个目录全空**
- `certbot.service` 就是 `ExecStart=/usr/bin/certbot -q renew --no-random-sleep-on-renew`，
  **没有任何 reload 动作**
- `cli.ini` 里也没有 hook

原本会这样演进：

1. 约 **2026-11-25**（到期前 30 天）certbot 自动续期 → 新证书文件落盘，一切"正常"。
2. nginx **仍在内存里发那张旧证书**（旧证书到 12-25 才过期，所以这一个月看不出问题，
   监控也发现不了）。
3. **2026-12-25 02:19:35 UTC 旧证书过期** → 访客看到过期证书 → 又是
   "Not Secure / broken HTTPS … certificate errors"，和这次故障症状一模一样。

**已执行的修复**：加了一个 certbot deploy hook。

```bash
# /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh （0755, root）
#!/bin/sh
set -e
systemctl reload nginx
```

放在这个目录下的可执行文件，certbot 在**成功续期**后会自动执行
（dry-run 不会执行，所以别指望在 `--dry-run` 里看到它跑）。

**验证（2026-09-26 04:49 UTC，在机器上实跑）**：

- 直接以 root 执行该 hook → `exit=0`
- nginx worker PID 由 `26002 29523` 变为 `29523 29532` —— **确认真的触发了 reload**
- `systemctl is-active nginx` → `active`；`nginx -t` → successful
- 复查公网：`https://demo.yourtravelview.com/en` → **200**，
  `http://…` → **301**，证书仍是 `CN=demo.yourtravelview.com` / 到期 12-25

> 顺带（**未执行**，只是提示）：`systemctl cat certbot.service` 和 reload 时的输出都提示
> *"unit file … changed on disk. Run 'systemctl daemon-reload'"* —— `certbot.service`
> 与 `nginx.service` 两个 unit 的磁盘版本都比 systemd 里加载的新。
> 不影响本次修复，得空 `sudo systemctl daemon-reload` 即可。

### 9.6 其它遗留项

- **443 的默认 server 就是演示站**：这台机器上**只有这一个 443 server 块**
  （`sites-available/default` 里两个 443 `listen` 都是注释掉的），所以任意不存在的 SNI
  连 `193.122.150.15:443` 都会拿到 demo 的证书和内容。要收口可在 `default` 里启用
  `listen 443 ssl default_server;` + `return 444;`。**本次没做** —— 这取决于
  "这台机器还想不想服务别的域名"，属于产品决定，不该顺手改。
- **`橙云` 注释与实测不符**：配置文件第 2 行写的是"Cloudflare 橙云 Proxied / 回源
  Full (strict)"，但实测 DNS 是**灰云**（A 记录直指 `193.122.150.15`，响应头无
  `cf-ray`，`server: nginx`）。两种模式下本配置都能工作（LE 证书都有效），
  但**要确认这块 A 记录到底想用哪种模式**：走橙云就少了源站暴露、且该把 CF SSL
  模式设成 Full (strict)；走灰云就得保证这台机器上的 LE 续期链路永远健康
  （见 §9.5）。
- **演示站没有 HSTS**（主站也没有）。配置里预留了指令但**故意注释掉**：
  这个站刚因证书问题整站不可用，HSTS 会让下次证书出问题时访客连"继续访问"都没有，
  先观察一个完整续期周期再开；且**不要**加 `includeSubDomains`（会波及走 CF 的主站）。
- **部署脚本没有单独留档**：这台机器上只有生产版的 `web/deploy/release.sh`
  （硬编码 `/opt/travelview` + `/etc/travelview/env`），演示站的发布是照着它做的，
  但**具体命令没记录**。已知发布根/软链/服务与生产机同构，能对上。
  `/opt/TravelView` 是 ubuntu 的克隆；`~/.pm2` 存在但当前服务是 systemd 管的。

