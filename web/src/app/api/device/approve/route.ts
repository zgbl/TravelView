import { NextResponse } from 'next/server';
import { randomBytes } from 'crypto';
import { requireUser } from '@/lib/auth';
import { one } from '@/lib/db';
import { normalizeUserCode } from '@/lib/device';

export const dynamic = 'force-dynamic';

/**
 * 第三步: 已登录的用户在网页上确认这台机器。
 *
 * 这里才生成 publish token 并绑到用户身上 ——
 * **确认动作必须发生在带会话的网页里**，桌面端不参与，
 * 否则谁拿到一串码都能换走别人的令牌。
 */
export async function POST(req: Request) {
  const user = await requireUser();
  if (!user) return NextResponse.json({ error: '请先登录' }, { status: 401 });

  const { code, label } = await req.json().catch(() => ({}));
  const normalized = normalizeUserCode(String(code ?? ''));
  if (normalized.length !== 8) {
    return NextResponse.json({ error: '这串码不对' }, { status: 400 });
  }

  const row = await one<{
    code: string; label: string | null; token: string | null;
  }>(`select code, label, token from device_codes
       where code = $1 and expires_at > now()`, [normalized]);
  if (!row) {
    return NextResponse.json(
      { error: '这串码无效或已经过期，回到 App 里重新生成一个' },
      { status: 404 });
  }
  if (row.token) {
    return NextResponse.json({ error: '这串码已经用过了' }, { status: 409 });
  }

  const token = `tv_${randomBytes(24).toString('hex')}`;
  await one(
    'insert into publish_tokens (token, user_id, label) values ($1,$2,$3)',
    [token, user.id, label ?? row.label ?? 'Desktop']);
  await one(
    `update device_codes set user_id = $2, approved_at = now(), token = $3
      where code = $1`, [normalized, user.id, token]);

  return NextResponse.json({ ok: true, label: row.label });
}
