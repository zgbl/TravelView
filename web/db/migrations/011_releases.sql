-- App 安装包。
--
-- **文件本身不进数据库**，只记元数据；安装包落在 RELEASES_DIR 下。
-- 一个平台可以有很多版本，但**同时只有一个是当前版本** —— 下载页只给
-- 当前版本，老版本留着是为了出问题时能让用户退回去。
create table if not exists app_releases (
  id           uuid primary key default gen_random_uuid(),
  -- macos / windows / android / ios
  platform     text not null,
  -- 语义化版本，如 1.2.0。同一平台同一版本只能有一条
  version      text not null,
  -- 磁盘上的文件名（不含目录）。ios 走 App Store 时可以为空
  filename     text,
  bytes        bigint not null default 0,
  -- sha256，给用户核对下载完整性用
  checksum     text,
  -- 外部下载地址: iOS 只能指向 App Store，Android 也可能走商店
  external_url text,
  -- 更新说明，markdown
  notes        text not null default '',
  -- 当前版本。每个平台**至多一条为真**，靠下面这个唯一索引兜住
  is_current   boolean not null default false,
  downloads    bigint not null default 0,
  created_at   timestamptz not null default now(),
  unique (platform, version)
);

-- "每个平台只有一个当前版本"是业务规则，**用数据库兜住** ——
-- 靠应用代码在两条 update 之间保证，并发下必然出现两个当前版本
create unique index if not exists app_releases_current
  on app_releases (platform) where is_current;

create index if not exists app_releases_platform_created
  on app_releases (platform, created_at desc);
