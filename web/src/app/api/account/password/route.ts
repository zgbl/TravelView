import { NextResponse } from 'next/server';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { requireUser } from '@/lib/auth';
import { one } from '@/lib/db';

/**
 * 改密码。
 *
 * **必须验证当前密码**，哪怕人已经登录了 —— 会话可能是别人在
 * 没锁屏的电脑上捡到的，改密码是能把真正的主人锁在门外的操作。
 */
const Body = z.object({
  current: z.string().min(1),
  next: z.string().min(8, '新密码至少 8 位'),
});

export async function POST(req: Request) {
  const user = await requireUser();
  if (!user) return NextResponse.json({ error: '未登录' }, { status: 401 });

  const parsed = Body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0]?.message ?? '参数不对' },
      { status: 400 },
    );
  }

  const row = await one<{ password_hash: string | null }>(
    'select password_hash from users where id = $1', [user.id]);
  if (!row?.password_hash) {
    return NextResponse.json({ error: '这个账号没有设置过密码' }, { status: 400 });
  }

  const ok = await bcrypt.compare(parsed.data.current, row.password_hash);
  if (!ok) {
    return NextResponse.json({ error: '当前密码不对' }, { status: 403 });
  }

  const hash = await bcrypt.hash(parsed.data.next, 10);
  await one('update users set password_hash = $2 where id = $1',
    [user.id, hash]);

  // 桌面端和手机端用的是长期令牌，不受这次改密影响 ——
  // 想把设备踢掉要去账户页吊销令牌。这里不悄悄替用户做那个决定。
  return NextResponse.json({ ok: true });
}
