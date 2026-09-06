-- 006 付费页需要的两处小改动。可重复执行。
--
-- 1) payments.credits_granted: 这笔付款到底给了几篇。
--    额度包的"一次给几篇"以后一定会调（$10 现在给 5 篇，将来可能给 8 篇），
--    只记 kind 的话，事后对账根本还原不出当时给了多少。
-- 2) payments 按用户查的索引: 账单页每次打开都按 user_id 倒序取 10 条。

alter table payments add column if not exists credits_granted int not null default 0;

create index if not exists payments_user_idx
  on payments(user_id, created_at desc);

-- 历史数据回填: 旧代码里一次性付款固定给 1 篇
update payments set credits_granted = 1
 where credits_granted = 0
   and kind in ('onetime', 'credits_1')
   and status = 'paid';
