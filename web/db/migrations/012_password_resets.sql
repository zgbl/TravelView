-- 忘记密码。
--
-- **表里存的是 token 的 sha256，不是 token 本身。**
-- 数据库被看一眼（备份文件、日志、误导出）就等于所有在途的重置链接
-- 都能被拿去改密码 —— 存哈希的话，拿到的人什么也做不了。
--
-- 一条记录只能用一次（used_at），而且有效期很短：这条链接的权力
-- 和密码本身一样大，躺在邮箱里越久越危险。
create table if not exists password_resets (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references users(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  used_at    timestamptz,
  -- 只为排查滥用，不做任何画像
  requested_ip text,
  created_at timestamptz not null default now()
);

create index if not exists password_resets_user
  on password_resets (user_id, created_at desc);
