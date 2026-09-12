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

> 目标：`https://yourtravelview.com` 能打开、能注册、能收钱、
> 桌面端能发布上去，拿到永久公开链接。
> 和 TensuGo 同机共存，**不动 TensuGo 的任何东西**。
>
> 域名: `yourtravelview.com` 是正式域名；`www.yourtravelview.com` 301 到裸域；
> 老域名 `travelview.blackrice.top` 继续直接服务（已发出的公开链接不会断），
> 但账号类页面会 301 到正式域名 —— 原因见
> `docs/oci-travelview-deploy-runbook.md` §6.5。

---

## 0.5 部署 / CI/CD —— 这一台已经跑起来了（最重要，先看这节）

### 已经配好「GitHub 推送 → 自动部署」（每 3 分钟检查一次）

- 调度: /etc/cron.d/travelview-autodeploy -> */3 * * * * root /usr/local/bin/travelview-autodeploy.sh
- 机制: 每 3 分钟 git fetch origin main; 只有当要部署的 web/ 代码有改动才触发 release.sh
  (零停机: 先构建到带时间戳新目录, 成功才切 current 软链并 systemctl restart travelview-web)。
  桌面端 / 纯文档改动不触发, 免得白重建。
- 用 flock 防重入; 日志在 /var/log/travelview-autodeploy.log。
- 平时你只要 push 到 GitHub, <=3 分钟后服务器自动上线; 构建失败不会动线上(仍跑旧版),
  并把失败记进日志、发报警邮件(见下)。

### 想马上上线, 不等那 3 分钟 —— 一条命令

```bash
sudo bash /usr/local/bin/travelview-autodeploy.sh
```
它会立刻 fetch -> 比对 -> 拉取 -> 构建 -> 切版本 -> 重启。没新改动就瞬间退出。

### 想自己一步步来 (= 手动 git pull + 构建 + 重启)

```bash
cd /opt/travelview/src
sudo git fetch origin main
sudo git reset --hard origin/main          # 或: sudo git pull --ff-only origin main
sudo bash web/deploy/release.sh            # 内部自动: npm install + next build + 切 current + 重启
```

> 注意: /opt/travelview/src 属 travelview 用户, 所以 git 命令**必须加 sudo**。
> 服务器已配好 safe.directory, 直接 sudo git pull 即可(不用再带 -c safe.directory)。
> 若换新机器遇到 "dubious ownership", 跑一次:
> sudo git config --global --add safe.directory /opt/travelview/src

> release.sh 结尾会自己 systemctl restart travelview-web, 不用再手动重启。
> 只有当你改了 /etc/travelview/env(运行配置, 没动代码)时才需要单独:
> sudo systemctl restart travelview-web

### 怎么确认这次部署上没上 / 出问题先看

```bash
sudo ls -l /opt/travelview/web/current        # current 指向哪个版本
sudo tail -50 /var/log/travelview-autodeploy.log
sudo journalctl -u travelview-web -n 50        # 服务日志
```

### 回滚到上一个版本

```bash
sudo ls -1t /opt/travelview/web/releases
sudo ln -sfn /opt/travelview/web/releases/<上一个时间戳> /opt/travelview/web/current
sudo systemctl restart travelview-web
```

### 失败自动发邮件报警

部署失败会调 /usr/local/bin/send-alert.sh 发到 carson_tu@hotmail.com。
工具与脚本已装好, 只差在 /etc/travelview/smtp.env(含 smtp.pass)里填 SMTP 发件账号即可生效。

---

## 0. 这台服务器上的分工

| | TensuGo | TravelView |
|---|---|---|
| 域名 | 原来那个 | `yourtravelview.com`（正式域名，CF 橙云）+ `www` 301 到裸域 |
| 老域名 | — | `travelview.blackrice.top` 内容照常服务，账号类页面 301 到正式域名 |
| Node 端口 | 原来那个 | `127.0.0.1:3001` |
| 代码 | 原来那里 | `/opt/travelview/` |
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
2. 主机名**一次全填上**：`yourtravelview.com`、`*.yourtravelview.com`、
   `*.blackrice.top`、`blackrice.top`
   （漏了哪个，对应域名在 CF **Full (strict)** 下就会 526）
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

> **实际部署记录在 `docs/oci-travelview-deploy-runbook.md`** ——
> 那份是这台机器上真正跑成的步骤和踩过的坑，和本文有出入时以那份为准。
> 目录是 `/opt/travelview/`（和 `/opt/tensugo` 并列）。

## 3. 拉代码 + 初始化

```bash
sudo mkdir -p /opt/travelview
sudo chown ubuntu:ubuntu /opt/travelview
git clone <你的仓库地址> /opt/travelview/src
cd /opt/travelview/src

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
| `TRAVELVIEW_DATABASE_URL` | 把脚本打印的数据库密码填进去 |
| `STRIPE_SECRET_KEY` | 先用 `sk_test_...` 跑通 |
| `STRIPE_PRICE_ONETIME` | Stripe 后台建一个「单篇发布」价格，复制 `price_...` |

`STRIPE_WEBHOOK_SECRET` 等第 6 节配完 webhook 再回来填。

建表：

```bash
set -a; . /etc/travelview/env; set +a
psql "$TRAVELVIEW_DATABASE_URL" -f /opt/travelview/src/web/db/schema.sql
```

---

## 4. 上线

```bash
sudo cp /opt/travelview/src/web/deploy/travelview-web.service \
        /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable travelview-web

cd /opt/travelview/src
sudo bash web/deploy/release.sh
```

`release.sh` 也是**可以重复跑**的：它先完整构建到一个带时间戳的新目录，
最后一步才切 `current` 软链并重启。构建挂了线上还是旧版本，一点没动。
出问题回滚就是把软链指回上一个版本再 `systemctl restart`。

nginx：

```bash
# 站点文件 + 应用片段（片段被两个 443 块 include，两个都得放）
sudo mkdir -p /etc/nginx/snippets
sudo cp /opt/travelview/src/web/deploy/nginx-travelview-app.conf \
        /etc/nginx/snippets/travelview-app.conf
sudo cp /opt/travelview/src/web/deploy/nginx-travelview.conf \
        /etc/nginx/sites-available/travelview
sudo ln -s /etc/nginx/sites-available/travelview /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

新老域名**各用一张证书**（SNI 决定用哪张），两对文件都要在位：

| 域名 | 证书 |
|---|---|
| `yourtravelview.com` / `www.yourtravelview.com` | `/etc/ssl/travelview/yourtravelview_origin.pem` + `.key` |
| `travelview.blackrice.top` | `/etc/ssl/travelview/origin.pem` + `.key`（老的那对，别动） |

`nginx -t` 一定要过再 reload —— 配置有错直接 reload 会**连 TensuGo 一起挂**。

---

## 5. 冒烟测试（按顺序，一步不过就停）

1. `curl -I https://yourtravelview.com` 返回 200
2. 浏览器打开，落地页出来
3. 注册账号，能登录
4. `/pricing` 付款，测试卡 `4242 4242 4242 4242`，任意未来日期 + 任意 CVC
5. `/account` 看到额度到账（**没到账就是 webhook 没通，看第 6 节**）
6. `/account` 生成发布令牌
7. 桌面端「生成旅行回顾」→ 导出 → 发布，域名填 `https://yourtravelview.com`
8. 打开返回的公开链接 —— 照片、地图、路线、文字都在
9. 服务器上 `ls /var/lib/travelview/media/s/` —— 图片确实落盘了

---

## 6. Stripe Webhook

**权益只在 webhook 里发放**，这步不通，用户付了钱也拿不到额度。

1. Stripe → Developers → Webhooks → Add endpoint
2. 地址 `https://yourtravelview.com/api/stripe/webhook`
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
pg_dump "$TRAVELVIEW_DATABASE_URL" | gzip > /var/backups/tv-$(date +%F).sql.gz
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
[ ] git clone 到 /opt/travelview/src
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

---

## 附录 B. 接通 Stripe（拿到账号之后）

代码已经写好，**只差三个环境变量**。在此之前网站正常运行：
公测期本来就免费，定价页的按钮会明确说"支付还没开通"，不会假装能点。

### B.1 在 Stripe 后台建两个价格

Products → Add product，各建一个 Price，记下 `price_...`：

| 用途 | 类型 |
|---|---|
| 单篇发布 | One time |
| 一年不限篇数 | Recurring / Yearly（可以先不做） |

### B.2 填进服务器

```bash
sudo nano /etc/travelview/env
```

```bash
STRIPE_SECRET_KEY=sk_test_...        # 先用测试密钥跑通，再换 sk_live_
STRIPE_PRICE_ONETIME=price_...
STRIPE_PRICE_SUBSCRIPTION=price_...  # 没有就留空
```

```bash
sudo systemctl restart travelview-web
```

**密钥只放这个文件，不进数据库、不进后台表单。** 一个能读写支付密钥的网页
本身就是最值钱的攻击目标，而且密钥一旦进了库，备份、日志、截图里到处都是它。
后台 `/admin` 只**显示**配没配好，不提供填写入口。

### B.3 Webhook（这一步不通，用户付了钱拿不到东西）

1. Stripe → Developers → Webhooks → Add endpoint
2. 地址 `https://yourtravelview.com/api/stripe/webhook`
3. 事件勾这五个：

```text
checkout.session.completed
customer.subscription.created
customer.subscription.updated
customer.subscription.deleted
invoice.payment_failed
```

4. 把 `whsec_...` 填进 `STRIPE_WEBHOOK_SECRET`，重启服务
5. 后台点 "Send test webhook"，确认返回 200

再跑一次幂等表的迁移：

```bash
cd /opt/travelview/src/web
set -a; . /etc/travelview/env; set +a
npm run db:migrate           # 先看还差哪几条
npm run db:migrate:apply     # 再真的跑
```

### B.4 为什么这么设计

| 决定 | 原因 |
|---|---|
| **权益只在 webhook 里发放** | "支付成功"的跳转页任何人都能直接访问；唯一可信的是 Stripe 签名过的回调 |
| **事件去重表** | Stripe 会重发同一事件（超时、5xx、它的重试策略），没有它一次付款可能加两次额度 |
| 幂等表缺失时**照发不误** | 宁可重复也不能吞掉付款 —— 重复了还能人工退，吞了是用户真花钱没拿到东西 |
| 订阅到期时间**取 Stripe 的 `current_period_end`** | 不自己算"一年后"，续费、改期、比例退款都以它为准 |
| 扣款失败**不立刻停权益** | 多半只是卡过期，标成 `past_due`，到期自然失效；粗暴断服会赶走本来愿意换卡的人 |
| 有客户门户 `/api/billing` | 退订找不到入口的用户，最后都会变成你的邮件和退款纠纷 |

### B.5 冒烟测试

用测试卡 `4242 4242 4242 4242`（任意未来日期 + 任意 CVC）：

```text
[ ] /pricing 点购买 -> 跳到 Stripe
[ ] 付款完成 -> 回到 /account，额度 +1
[ ] Stripe 后台 Webhooks 那条事件是 200
[ ] 再点一次 "Resend" 那个事件 -> 额度**不再增加**（幂等生效）
[ ] 换成 sk_live_ 和正式 price 后，重新跑一遍前两步
```
