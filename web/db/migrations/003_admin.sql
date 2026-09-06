-- 管理员标记。**第一个注册的人自动成为管理员**（见 api/signup），
-- 之后的注册都是普通用户。这样不用先手工往库里塞一条记录。
alter table users add column if not exists is_admin boolean not null default false;
