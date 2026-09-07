-- 010 更新计次: 前 5 次更新免费，第 6 次起每次扣 0.5 篇额度。可重复执行。
--
-- 为什么要计次: 更新是正当且高频的动作（改错别字、换封面、删掉一张照片），
-- 每次都收钱等于惩罚"把东西做好"。但它确实有成本 ——
-- 每次更新都要重传照片、重写文件。所以给足免费额度，超过了才象征性收一点。

alter table stories add column if not exists update_count int not null default 0;

-- 0.5 篇怎么记: story_credits 是整数，不改它的类型。
-- 欠下的半篇记在这里(0 或 1)，凑满一篇时再从 story_credits 扣 1。
-- 这样账目永远是精确的，也不会因为浮点数出现 0.30000000000000004。
alter table users add column if not exists credit_half int not null default 0;
