import { NextResponse } from 'next/server';
import { randomBytes } from 'crypto';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { one } from '@/lib/db';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * 桌面端登录。邮箱 + 密码，换一个长期发布令牌。
 *
 * **App 不保存密码**，只保存换回来的令牌；令牌可以在网站账户页随时吊销。
 * 密码只在这一次请求里出现，验完就丢。
 */
const Body = z.object({
  email: z.string().trim().toLowerCase().email(),
  password: z.string().min(1),
  label: z.string().trim().max(60).optional(),
});

export async function POST(req: Request) {
  const parsed = Body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: '邮箱或密码格式不对' }, { status: 400 });
  }
  const { email, password, label } = parsed.data;

  const user = await one<{
    id: string; password_hash: string | null; banned_at: string | null;
  }>('select id, password_hash, banned_at from users where email = $1',
    [email]);

  // 邮箱不存在和密码错给同一句话 —— 否则这个接口就成了一个查
  // "这个邮箱注册过没有"的工具
  const ok = user?.password_hash
    ? await bcrypt.compare(password, user.password_hash)
    : false;
  if (!ok) {
    return NextResponse.json({ error: '邮箱或密码不对' }, { status: 401 });
  }
  if (user!.banned_at) {
    return NextResponse.json({ error: '这个账号已被停用' }, { status: 403 });
  }

  const token = `tv_${randomBytes(24).toString('hex')}`;
  await one(
    'insert into publish_tokens (token, user_id, label) values ($1,$2,$3)',
    [token, user!.id, label ?? 'Desktop']);

  return NextResponse.json({ token });
}
