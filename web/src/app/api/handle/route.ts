import { NextResponse } from 'next/server';
import { z } from 'zod';
import { requireUser } from '@/lib/auth';
import { one } from '@/lib/db';

export const dynamic = 'force-dynamic';

/**
 * 设置公开主页的地址（handle）。
 *
 * 规则刻意收紧: 只允许小写字母、数字、下划线，3-20 位。
 * 允许大小写混用会带来"Alice 和 alice 是不是同一个人"的麻烦；
 * 保留字单独挡掉 —— 别让人抢注 /u/admin。
 */
const RESERVED = new Set([
  'admin', 'api', 'about', 'account', 'billing', 'help', 'login', 'logout',
  'signup', 'pricing', 'stories', 'story', 'support', 'settings', 'link',
  'u', 's', 'www', 'mail', 'root', 'null', 'undefined', 'me', 'new',
]);

const Body = z.object({
  handle: z.string().trim().toLowerCase()
    .regex(/^[a-z0-9_]{3,20}$/, 'BAD_HANDLE'),
});

export async function PATCH(req: Request) {
  const user = await requireUser();
  if (!user) return NextResponse.json({ error: '请先登录' }, { status: 401 });

  const parsed = Body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: 'BAD_HANDLE' }, { status: 400 });
  }
  const { handle } = parsed.data;
  if (RESERVED.has(handle)) {
    return NextResponse.json({ error: 'TAKEN' }, { status: 409 });
  }

  try {
    await one('update users set handle = $2 where id = $1', [user.id, handle]);
  } catch {
    // 唯一索引撞了 —— 这是唯一可能的失败，不用去猜别的原因
    return NextResponse.json({ error: 'TAKEN' }, { status: 409 });
  }
  return NextResponse.json({ ok: true, handle });
}
