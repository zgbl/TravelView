-- 封禁标记。封禁只挡新的发布，不动用户已经发布的内容 ——
-- 那是他的东西，要下架得单独决定。
alter table users add column if not exists banned_at timestamptz;
