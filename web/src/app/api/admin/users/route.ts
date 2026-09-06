import { NextResponse } from 'next/server';
import { z } from 'zod';
import { requireAdmin } from '@/lib/admin';
import { one } from '@/lib/db';

/**
 * 管理员对用户的操作。
 *
 * 只做三件真正需要的事: 给/收管理员、加发布额度、封禁。
 * **没有"删除用户"** —— 删了就没了，而封禁可以撤销；
 * 真要删，让用户自己在账户页删，那条路径本来就有。
 */
const Body = z.object({
  userId: z.string().uuid(),
  action: z.enum(['grant_admin', 'revoke_admin', 'add_credits', 'ban', 'unban']),
  amount: z.number().int().min(1).max(1000).optional(),
});

export async function POST(req: Request) {
  const admin = await requireAdmin();
  if (!admin) return NextResponse.json({ error: 'not found' }, { status: 404 });

  const parsed = Body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: '参数不对' }, { status: 400 });
  }
  const { userId, action, amount } = parsed.data;

  // 不能把自己的管理员摘掉 —— 一不小心就没人能进后台了
  if (action === 'revoke_admin' && userId === admin.id) {
    return NextResponse.json(
      { error: '不能撤销自己的管理员' }, { status: 400 });
  }
  if (action === 'ban' && userId === admin.id) {
    return NextResponse.json({ error: '不能封禁自己' }, { status: 400 });
  }

  switch (action) {
    case 'grant_admin':
      await one('update users set is_admin = true where id = $1', [userId]);
      break;
    case 'revoke_admin':
      await one('update users set is_admin = false where id = $1', [userId]);
      break;
    case 'add_credits':
      await one(
        'update users set story_credits = story_credits + $2 where id = $1',
        [userId, amount ?? 1]);
      break;
    case 'ban':
      // 封禁 = 吊销全部发布令牌 + 标记。已发布的故事不动，
      // 那是用户的东西，要下架得单独决定
      await one('update users set banned_at = now() where id = $1', [userId]);
      await one(`update publish_tokens set revoked_at = now()
                  where user_id = $1 and revoked_at is null`, [userId]);
      break;
    case 'unban':
      await one('update users set banned_at = null where id = $1', [userId]);
      break;
  }
  return NextResponse.json({ ok: true });
}
