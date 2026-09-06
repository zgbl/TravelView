-- 流量统计。刻意**不记录任何访客身份** —— 不存 IP、不下 cookie、不做指纹。
-- 只按天数数字，够回答"有没有人看"这个问题，也不给自己招隐私麻烦。

create table if not exists view_daily (
  day    date not null,
  slug   text not null,
  count  bigint not null default 0,
  primary key (day, slug)
);

create index if not exists view_daily_day_idx on view_daily(day desc);

-- 总数和当日数一起加。总数留在 stories 上，页面直接读，不用聚合。
create or replace function bump_story_view(p_slug text) returns void as $$
  with bump as (
    update stories set view_count = view_count + 1 where slug = p_slug
    returning slug
  )
  insert into view_daily (day, slug, count)
  select current_date, slug, 1 from bump
  on conflict (day, slug) do update set count = view_daily.count + 1;
$$ language sql;
