-- Webhook 幂等表。
--
-- Stripe **会重发**同一个事件（超时、5xx、它自己的重试策略），
-- 没有这张表的话，一次付款可能加两次额度。主键冲突即已处理过。
create table if not exists stripe_events (
  id           text primary key,     -- Stripe 的 event id，evt_...
  type         text not null,
  received_at  timestamptz not null default now()
);
