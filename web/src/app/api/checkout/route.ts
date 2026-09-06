import { NextResponse } from 'next/server';
import { requireUser } from '@/lib/auth';
import { one } from '@/lib/db';
import { PLANS, stripe, stripeStatus, type PlanKey } from '@/lib/stripe';

/** 创建 Stripe Checkout 会话。支付成功由 webhook 落权益，这里只负责跳转。 */
export async function POST(req: Request) {
  const user = await requireUser();
  if (!user) return NextResponse.json({ error: '请先登录' }, { status: 401 });

  // 还没接通支付时，给一句人话，而不是把 Stripe 的英文报错抛给用户
  if (!stripeStatus().secretKey) {
    return NextResponse.json(
      { error: 'PAYMENT_NOT_READY', message: '支付还没开通，公测期间发布本来就是免费的' },
      { status: 503 });
  }

  const { plan } = (await req.json().catch(() => ({}))) as { plan?: PlanKey };
  const chosen = plan && PLANS[plan];
  if (!chosen?.priceId) {
    return NextResponse.json({ error: '这个套餐还没配置' }, { status: 400 });
  }

  // Stripe customer 只建一次，之后复用，方便对账和做客户门户
  let row = await one<{ stripe_customer_id: string | null }>(
    'select stripe_customer_id from users where id = $1',
    [user.id],
  );
  let customerId = row?.stripe_customer_id ?? null;
  if (!customerId) {
    const customer = await stripe.customers.create({
      email: user.email,
      metadata: { userId: user.id },
    });
    customerId = customer.id;
    await one('update users set stripe_customer_id = $1 where id = $2',
      [customerId, user.id]);
  }

  const site = process.env.NEXT_PUBLIC_SITE_URL;
  const session = await stripe.checkout.sessions.create({
    mode: chosen.mode,
    customer: customerId,
    line_items: [{ price: chosen.priceId, quantity: 1 }],
    success_url: `${site}/account?paid=1`,
    cancel_url: `${site}/pricing`,
    client_reference_id: user.id,
    // 订阅要能自助取消，否则退款和投诉都会变成你的人工客服工作
    ...(chosen.mode === 'subscription'
      ? { subscription_data: { metadata: { userId: user.id } } }
      : {}),
    metadata: { userId: user.id, plan: chosen.key },
  });

  return NextResponse.json({ url: session.url });
}
