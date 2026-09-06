import { requireUser } from './auth';
import { one } from './db';

/**
 * 管理员判定。
 *
 * 两条来源，任一满足即可:
 *   1. `users.is_admin` —— 第一个注册的人自动带上
 *   2. `ADMIN_EMAILS` 环境变量（逗号分隔）—— 万一数据库里的标记被弄丢了，
 *      还有一条不依赖数据的后路
 *
 * 后台页面必须**每次请求都在服务端查一遍**，不能只靠前端藏起来入口。
 */
export async function requireAdmin() {
  const user = await requireUser();
  if (!user) return null;

  const envAdmins = (process.env.ADMIN_EMAILS ?? '')
    .split(',').map((e) => e.trim().toLowerCase()).filter(Boolean);
  if (envAdmins.includes(user.email.toLowerCase())) return user;

  const row = await one<{ is_admin: boolean }>(
    'select is_admin from users where id = $1', [user.id]);
  return row?.is_admin ? user : null;
}
