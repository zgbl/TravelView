import { NextResponse } from 'next/server';
import { one } from '@/lib/db';

export const dynamic = 'force-dynamic';

/**
 * 第二步: 桌面端拿 device_code 轮询。
 *
 * 三种回答，和 OAuth 设备流一致，App 照着分支写就行:
 *   authorization_pending  还没人确认，继续等
 *   expired_token          超时了，重新走第一步
 *   200 + token            确认了，这是长期发布令牌
 *
 * 令牌**只返回一次**: 取走后就把 device_codes 那一行删掉，
 * 避免同一串码被反复兑换（比如日志或截图泄露了 device_code）。
 */
export async function POST(req: Request) {
  const { deviceCode } = await req.json().catch(() => ({}));
  if (!deviceCode) {
    return NextResponse.json({ error: 'invalid_request' }, { status: 400 });
  }

  const row = await one<{
    code: string; token: string | null; expires_at: string;
  }>('select code, token, expires_at from device_codes where device_code = $1',
    [deviceCode]);

  if (!row) {
    return NextResponse.json({ error: 'expired_token' }, { status: 400 });
  }
  if (new Date(row.expires_at) < new Date()) {
    return NextResponse.json({ error: 'expired_token' }, { status: 400 });
  }
  if (!row.token) {
    return NextResponse.json({ error: 'authorization_pending' },
      { status: 428 });
  }

  await one('delete from device_codes where device_code = $1', [deviceCode]);
  return NextResponse.json({ token: row.token });
}
