import { NextResponse } from 'next/server';
import { one, query } from '@/lib/db';
import {
  DEVICE_CODE_TTL_MS, formatUserCode, newDeviceCode, newUserCode,
} from '@/lib/device';
import { siteUrl } from '@/lib/stripe';

export const dynamic = 'force-dynamic';

/**
 * 第一步: 桌面端申请一对码。**不需要任何身份** —— 这一步还没有用户。
 *
 * 返回的 user_code 给人看，device_code 给机器轮询用。
 */
export async function POST(req: Request) {
  const { label } = await req.json().catch(() => ({}));

  // 顺手清掉过期的，不给这张表留一个只增不减的坑
  await query('delete from device_codes where expires_at < now()')
    .catch(() => {});

  const code = newUserCode();
  const deviceCode = newDeviceCode();
  const expires = new Date(Date.now() + DEVICE_CODE_TTL_MS);

  await one(
    `insert into device_codes (code, device_code, label, expires_at)
     values ($1,$2,$3,$4)`,
    [code, deviceCode, String(label ?? 'Desktop').slice(0, 60), expires]);

  return NextResponse.json({
    userCode: formatUserCode(code),
    deviceCode,
    verifyUrl: `${siteUrl()}/link`,
    expiresIn: Math.floor(DEVICE_CODE_TTL_MS / 1000),
    interval: 3,
  });
}
