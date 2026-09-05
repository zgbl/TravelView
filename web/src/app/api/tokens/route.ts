import { NextResponse } from 'next/server';
import { randomBytes } from 'crypto';
import { requireUser } from '@/lib/auth';
import { one, query } from '@/lib/db';

/** 生成给桌面端用的发布令牌 */
export async function POST(req: Request) {
  const user = await requireUser();
  if (!user) return NextResponse.json({ error: '请先登录' }, { status: 401 });
  const { label } = await req.json().catch(() => ({}));

  const token = `tv_${randomBytes(24).toString('hex')}`;
  await one(
    'insert into publish_tokens (token, user_id, label) values ($1,$2,$3)',
    [token, user.id, label ?? 'Desktop']);
  // 只在创建时返回一次完整令牌
  return NextResponse.json({ token });
}

export async function DELETE(req: Request) {
  const user = await requireUser();
  if (!user) return NextResponse.json({ error: '请先登录' }, { status: 401 });
  const { token } = await req.json().catch(() => ({}));
  await query(
    'update publish_tokens set revoked_at = now() where token = $1 and user_id = $2',
    [token, user.id]);
  return NextResponse.json({ ok: true });
}
