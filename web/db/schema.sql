-- TravelView 网站数据库
--
-- 刻意保持极简: 只支撑「注册 -> 付费 -> 发布 -> 公开链接」这条闭环。
-- 没有社区、评论、关注、积分体系 —— 那些等有了付费用户再说。
--
-- 用普通 Postgres，不依赖任何厂商特性，所以 Neon / Supabase / 你 OCI 上那台
-- 都能直接跑，将来和 TensuGo 共用一个实例也没问题。

create extension if not exists pgcrypto;

create table if not exists users (
  id              uuid primary key default gen_random_uuid(),
  email           text not null unique,
  password_hash   text,
  name            text,
  created_at      timestamptz not null default now(),

  -- Stripe
  stripe_customer_id text unique,

  -- 权益。两种模式并存，方便以后调整定价而不用改表:
  --   story_credits > 0        每发布一篇扣一个
  --   subscription_status='active'  不限篇数
  story_credits      int not null default 0,
  subscription_status text,
  subscription_until  timestamptz
);

-- 桌面端用它上传，避免在 App 里存用户密码
create table if not exists publish_tokens (
  token       text primary key,
  user_id     uuid not null references users(id) on delete cascade,
  label       text,
  created_at  timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at  timestamptz
);

create table if not exists stories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users(id) on delete cascade,

  -- 公开地址的一部分，不可猜测: /s/<slug>
  slug        text not null unique,

  title       text not null,
  subtitle    text,
  cover_path  text,

  -- 完整 manifest（含压缩后的 route geometry）。几十 KB，直接放库里最省事。
  manifest    jsonb not null,

  -- 冗余出来便于列表页展示和排序，不用每次解 manifest
  start_date  date,
  end_date    date,
  day_count   int not null default 0,
  stop_count  int not null default 0,
  photo_count int not null default 0,
  distance_meters bigint not null default 0,

  visibility  text not null default 'public',  -- public | unlisted | private
  published_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  view_count  bigint not null default 0
);

create index if not exists stories_user_idx on stories(user_id, created_at desc);

-- 支付记录。留着是为了对账和以后做退款，不参与业务逻辑判断。
create table if not exists payments (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid references users(id) on delete set null,
  stripe_session_id  text unique,
  stripe_payment_intent text,
  kind               text not null,          -- onetime | subscription
  amount_cents       int,
  currency           text,
  status             text not null,
  created_at         timestamptz not null default now()
);

-- 简单的浏览计数，不记录任何访客身份
create or replace function bump_story_view(p_slug text) returns void as $$
  update stories set view_count = view_count + 1 where slug = p_slug;
$$ language sql;
