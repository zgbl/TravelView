import { createHash } from 'node:crypto';
import { NextResponse } from 'next/server';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { one, query } from '@/lib/db';

export const dynamic = 'force-dynamic';

const Body = z.object({
  token: z.string().min(20),
  password: z.string().min(8, '密码至少 8 位'),
});

/**
 * 「忘记密码」第二步：拿一次性链接换一个新密码。
 *
 * 三道闸门缺一不可：**没用过、没过期、对得上某个用户**。
 * 用掉之后立刻标记 used_at —— 链接躺在邮箱里，谁翻到都能再点一次。
 */
export async function POST(req: Request) {
  const parsed = Body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0]?.message ?? '参数不对' },
      { status: 400 },
    );
  }
  const { token, password } = parsed.data;
  const hash = createHash('sha256').update(token).digest('hex');

  const row = await one<{ id: string; user_id: string; email: string }>(
    `select r.id, r.user_id, u.email
       from password_resets r join users u on u.id = r.user_id
      where r.token_hash = $1 and r.used_at is null and r.expires_at > now()`,
    [hash],
  );
  if (!row) {
    // 过期、用过、伪造 —— 对用户来说是同一件事：这条链接不能用了，重来一次
    return NextResponse.json(
      { error: '这个链接已经失效了，请重新申请一次' }, { status: 400 });
  }

  const pw = await bcrypt.hash(password, 10);
  await query('update users set password_hash = $2 where id = $1',
    [row.user_id, pw]);
  await query('update password_resets set used_at = now() where id = $1',
    [row.id]);

  // 同一个人可能还有别的在途链接，一并作废
  await query(
    `update password_resets set used_at = now()
      where user_id = $1 and used_at is null`, [row.user_id]);

  // 把邮箱回给前端，好让它直接登录进去 —— 密码是他刚定的，
  // 再把人丢回登录页重输一遍纯属添堵
  return NextResponse.json({ ok: true, email: row.email });
}
