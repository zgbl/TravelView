import { NextResponse } from 'next/server';
import { z } from 'zod';
import { requireUser } from '@/lib/auth';
import { one } from '@/lib/db';

/** 用户改自己的资料。目前只有显示名。 */
const Body = z.object({ name: z.string().trim().max(40) });

export async function PATCH(req: Request) {
  const user = await requireUser();
  if (!user) return NextResponse.json({ error: '未登录' }, { status: 401 });

  const parsed = Body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: '名字太长了' }, { status: 400 });
  }
  // 空字符串存 null，别在库里留一堆空串
  await one('update users set name = $2 where id = $1',
    [user.id, parsed.data.name || null]);
  return NextResponse.json({ ok: true });
}
