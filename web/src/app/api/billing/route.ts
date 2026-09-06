import { NextResponse } from 'next/server';
import { requireUser } from '@/lib/auth';
import { one } from '@/lib/db';
import { stripe, stripeStatus } from '@/lib/stripe';

/**
 * Stripe 客户门户: 用户自己看发票、换卡、取消订阅。
 *
 * 这一个接口省掉的是**你以后所有的人工客服**——
 * 退订找不到入口的用户，最后都会变成你的邮件和退款纠纷。
 */
export async function POST() {
  const user = await requireUser();
  if (!user) return NextResponse.json({ error: '请先登录' }, { status: 401 });
  if (!stripeStatus().secretKey) {
    return NextResponse.json({ error: '支付还没开通' }, { status: 503 });
  }

  const row = await one<{ stripe_customer_id: string | null }>(
    'select stripe_customer_id from users where id = $1', [user.id]);
  if (!row?.stripe_customer_id) {
    return NextResponse.json({ error: '还没有付款记录' }, { status: 400 });
  }

  const portal = await stripe.billingPortal.sessions.create({
    customer: row.stripe_customer_id,
    return_url: `${process.env.NEXT_PUBLIC_SITE_URL}/account`,
  });
  return NextResponse.json({ url: portal.url });
}
