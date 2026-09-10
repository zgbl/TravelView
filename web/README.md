# TravelView Web

配套网站：注册、支付、接收桌面端发布的 Story、生成永久公开链接。

**独立于 tv_core / 桌面端**，可以单独开发和部署；共享的只有 Story manifest 这一份契约
（`src/lib/story.ts` 对应 `packages/tv_core/lib/src/story.dart`，改一边必须改另一边）。

## 跑起来

```bash
cd web
cp .env.example .env.local     # 填好数据库、Stripe、R2
npm install
psql "$TRAVELVIEW_DATABASE_URL" -f db/schema.sql
npm run dev
```

## 上线

看 `docs/deploy-web.md`（主线是部署到自己的 OCI 服务器，
Vercel + Neon 作为附录）。
部署前先跑一遍自检：

```bash
npm run preflight
```

## 技术选型与理由

| 层 | 选型 | 为什么 |
|---|---|---|
| 框架 | Next.js App Router + TypeScript | 页面和 API 一套代码，最快上线 |
| 数据库 | **普通 Postgres（`pg`）** | 换 Neon / Supabase / 你 OCI 那台只改 `TRAVELVIEW_DATABASE_URL` |
| 认证 | **Auth.js (NextAuth v5)** | 只依赖 `TRAVELVIEW_DATABASE_URL`，不绑定任何托管商 |
| 支付 | Stripe | 权益只在 webhook 里发放 |
| 图片 | 任何 S3 兼容存储 | 现用 OCI Object Storage；换 R2/MinIO 只改环境变量 |
| 地图 | MapLibre GL | 上线前把瓦片换成自托管 Protomaps |

`output: 'standalone'`，所以 `npm run build` 的产物能直接在 OCI 的 Node 上跑，
和 TensuGo 同机部署没问题。

## 关于 Supabase

你原本列的是 Supabase Auth + Postgres。我只在**认证**这一层偏离了：
Supabase Auth 会把用户表和会话绑在 Supabase 上，将来想搬到 OCI 就得改代码，
而你明确说了要能和 TensuGo 同机部署。

Supabase 仍然完全可用 —— 把它当作一个 Postgres 供应商，
`TRAVELVIEW_DATABASE_URL` 指过去即可。

## 目录

```
src/lib/story.ts        Story 类型 + polyline 解码（与 Dart 端同一契约）
src/components/         StoryRenderer / StoryMap 是视觉核心
src/app/s/[slug]/       公开页 + Open Graph 预览图
src/app/api/publish/    桌面端发布接口
db/schema.sql           全部表结构
docs/publish-api.md     桌面端要对接的协议
```
