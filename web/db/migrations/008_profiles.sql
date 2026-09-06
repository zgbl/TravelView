-- 008 用户主页 + 桌面端设备码登录 + 发布后原地更新。可重复执行。

-- ── 1. 公开主页的地址标识 ──
-- 用用户自选的 handle，不用 UUID: UUID 又长又丑，而且把内部主键暴露在
-- 分享链接里，以后想换标识就再也换不掉了。
-- 统一存小写，唯一索引建在 lower(handle) 上，避免 Alice / alice 抢注同一个名字。
alter table users add column if not exists handle text;
alter table users add column if not exists bio text;
alter table users add column if not exists profile_public boolean not null default true;

create unique index if not exists users_handle_key on users(lower(handle));

-- ── 2. 桌面端设备码登录 ──
-- App 显示一串码，用户在网页上确认，App 轮询换回长期令牌。
-- 好处是**桌面端永远不接触用户密码**，以后接 Google 登录也不用推倒重来。
create table if not exists device_codes (
  code        text primary key,            -- 用户看到并输入的短码，如 KDR-8Q2
  device_code text not null unique,        -- App 轮询时用的长随机串，不给用户看
  label       text,                        -- "MacBook Pro"，显示在确认页上
  user_id     uuid references users(id) on delete cascade,  -- 确认后才填
  approved_at timestamptz,
  token       text,                        -- 确认后生成的 publish token
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null
);

create index if not exists device_codes_expiry_idx on device_codes(expires_at);

-- ── 3. 图片的存放前缀 ──
-- 老数据是 s/<slug>/...，新数据是 u/<user uuid>/<年>/<月>/<slug>/...
-- 按用户和年月分目录，是为了将来单个用户的文件多到几万张时目录还能翻得动，
-- 也方便按用户整体迁移或清理。**记在行里而不是靠代码算**:
-- 算法会变，已经写在磁盘上的路径不会跟着变。
alter table stories add column if not exists media_prefix text;

update stories set media_prefix = 's/' || slug where media_prefix is null;
