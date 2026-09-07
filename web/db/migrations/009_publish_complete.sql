-- 009 发布改成两段式: 先建 Story 传图，全部传完才算发布、才扣额度。
--
-- 为什么: 一次发布上百张图，家用上行断一次是常态。
-- 原来在建 Story 时就扣额度，传到一半断了 —— 用户既没拿到能看的页面，
-- 额度还少了一个。**钱只能在东西真的交付之后收。**

-- 这一篇的额度扣过了没有。续传、重发都靠它保证只扣一次。
alter table stories add column if not exists credit_consumed boolean not null default false;

-- 已经在线上的那些当然算发布完成、算扣过了
update stories set credit_consumed = true
 where credit_consumed = false and published_at is not null;

-- published_at is null = 还在传/没传完，不对外显示
create index if not exists stories_live_idx
  on stories(user_id, published_at desc) where published_at is not null;
