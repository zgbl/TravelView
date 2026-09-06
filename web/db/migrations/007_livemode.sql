-- 007 给付款记录打上 Stripe 模式标记。可重复执行。
--
-- 为什么需要: 换 STRIPE_SECRET_KEY 就能在测试和正式之间切，但**数据库是同一个**。
-- 测试模式下的付款不扣真钱，发的额度却是真的。没有这一列，
-- 正式上线后就再也分不清"这 2 篇额度是测试留下的还是用户真金白银买的"。
--
-- 默认 false: 已有的记录都是测试期间产生的。

alter table payments add column if not exists livemode boolean not null default false;

create index if not exists payments_livemode_idx on payments(livemode, created_at desc);

-- 上线前清理测试数据用（**确认过再执行，默认注释掉**）:
--   update users u set story_credits = 0, subscription_status = null,
--                      subscription_until = null
--    where exists (select 1 from payments p
--                   where p.user_id = u.id and p.livemode = false);
--   delete from payments where livemode = false;
