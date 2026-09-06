import { NextResponse } from 'next/server';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { one } from '@/lib/db';

const Body = z.object({
  email: z.string().email(),
  password: z.string().min(8, '密码至少 8 位'),
  name: z.string().trim().max(40).optional(),
});

export async function POST(req: Request) {
  const parsed = Body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0]?.message ?? '参数不对' },
      { status: 400 },
    );
  }
  const { email, password, name } = parsed.data;
  const lower = email.toLowerCase();

  const existing = await one('select id from users where email = $1', [lower]);
  if (existing) {
    return NextResponse.json({ error: '这个邮箱已经注册过了' }, { status: 409 });
  }

  const hash = await bcrypt.hash(password, 10);
  const user = await one<{ id: string }>(
    'insert into users (email, password_hash, name) values ($1,$2,$3) returning id',
    [lower, hash, name?.trim() || null],
  );

  // 第一个注册的人就是站长。条件写在 SQL 里（要求全表只有这一行），
  // 万一同时来两个注册请求，也只有真正的第一个会拿到管理员。
  await one(
    `update users set is_admin = true
      where id = $1 and (select count(*) from users) = 1`,
    [user!.id],
  );
  return NextResponse.json({ id: user!.id });
}
