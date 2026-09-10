---
title: Stripe 多环境切换
---

# Stripe 多环境切换

## 一句话

**模式由 `STRIPE_SECRET_KEY` 的前缀决定，切换只改环境变量，代码一行不动。**
`sk_test_` = 测试模式，`sk_live_` = 正式模式。`/admin` 页面顶部会显示当前是哪个。

## 代码里保证了什么

| 要求 | 实现位置 |
|---|---|
| 密钥、webhook secret、5 条 price ID 全部来自 `process.env` | `src/lib/stripe.ts`，仓库里没有任何 `sk_`/`price_`/`whsec_` 字面量 |
| 回跳地址动态拼接 | `siteUrl()` 读 `NEXT_PUBLIC_SITE_URL`，缺失直接抛错而不是拼出 `undefined/...` |
| 验签只认环境变量 | `api/stripe/webhook/route.ts` 只用 `process.env.STRIPE_WEBHOOK_SECRET`，所以本地 Stripe CLI 转发和线上端点是同一套代码 |
| 模式显示 | `stripeMode()` → `/admin` 的 Live/Test 徽章 |
| price 实时核对 | `verifyPrices()` 用当前密钥去 Stripe 查每条 price，缓存 60 秒 |
| 测试数据可追溯 | `payments.livemode` 列（迁移 007），账单页给测试单据打 `TEST` 标 |

## 三套环境

| | SECRET_KEY | WEBHOOK_SECRET | SITE_URL |
|---|---|---|---|
| 本地开发 | `sk_test_` | `stripe listen` 每次给的 `whsec_` | `http://localhost:3000` |
| 测试服务器 | `sk_test_` | Test mode 端点的 `whsec_` | 测试域名 |
| 正式 | `sk_live_` | **Live mode** 端点的 `whsec_` | 正式 https 域名 |

本地开发：

```bash
stripe login
stripe listen --forward-to localhost:3000/api/stripe/webhook
# 把它打印的 whsec_... 填进 .env.local，然后
stripe trigger checkout.session.completed
```

## Link 的短信验证码

结账页出现「Confirm it's you / 输入发送到 ••62 的验证码」时，那是 **Stripe Link**
（Stripe 自己的一键支付，认出了这个邮箱或浏览器存过卡），
**不是我们的代码发的**，我们也没有任何接口能关掉那一次验证。

- 测试模式下输入 `000000` 即可通过，Stripe 不会真的发短信。
- 不想让它出现，两条路（选一条）：
  - Stripe 后台 → Settings → Payment methods → 关掉 Link；
  - 或者设 `STRIPE_PAYMENT_METHODS=card`，Checkout 就只提供银行卡。
    注意这会同时关掉 Apple Pay / Google Pay，除非把它们也列进去。

## 切到正式模式的检查清单

1. `/etc/travelview/env` 里换 **7 个值**：secret key、webhook secret、5 条 price ID。
   只换密钥不换 price ID 是最常见的事故 —— price 字符串看不出 test/live，
   要等第一个真实用户点下按钮才会 500。
2. `node scripts/preflight.mjs`。正式模式下它会把 https 域名和 `whsec_` 前缀
   当作硬性条件（不合格直接判失败，不是警告）。
3. 重启服务，打开 `/admin`：徽章应为 **Live Mode**，「价格核对」5 行全绿，
   每行显示的金额要和你在 Stripe 后台看到的一致。
4. 清理测试期间的权益（测试和正式共用同一个数据库，测试付款发的是真额度）：
   `db/migrations/007_livemode.sql` 末尾有现成的 SQL，确认过再执行。
5. 真卡小额跑一单，确认额度到账、`/account/billing` 的付款记录**没有** TEST 标记。

## 想再开发/改价怎么办

正式上线之后仍然可以随时回到测试：把那台开发机（或本地）的 env 换回 `sk_test_`
那一套即可，两边数据互不影响。**唯一要注意的是数据库**：如果开发环境连的是
生产库，测试付款会把假额度发给真实用户 —— 开发环境务必用独立的 `TRAVELVIEW_DATABASE_URL`。
