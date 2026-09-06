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

  try {
    await one(
      `insert into device_codes (code, device_code, label, expires_at)
       values ($1,$2,$3,$4)`,
      [code, deviceCode, String(label ?? 'Desktop').slice(0, 60), expires]);
  } catch (e) {
    // 最常见的就是 008 迁移没跑（没有 device_codes 表）。
    // 抛一整页 500 HTML 给桌面端，等于让人对着"失败了"三个字干瞪眼
    return NextResponse.json(
      { error: '服务器还没准备好设备登录（数据库迁移没跑完）' },
      { status: 503 });
  }

  return NextResponse.json({
    userCode: formatUserCode(code),
    deviceCode,
    verifyUrl: `${siteUrl()}/link`,
    expiresIn: Math.floor(DEVICE_CODE_TTL_MS / 1000),
    interval: 3,
  });
}
