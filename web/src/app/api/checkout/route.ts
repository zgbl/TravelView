import { NextResponse } from 'next/server';
import { requireUser } from '@/lib/auth';
import { one } from '@/lib/db';
import { PLANS, stripe, type PlanKey } from '@/lib/stripe';

/** 创建 Stripe Checkout 会话。支付成功由 webhook 落权益，这里只负责跳转。 */
export async function POST(req: Request) {
  const user = await requireUser();
  if (!user) return NextResponse.json({ error: '请先登录' }, { status: 401 });

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
    metadata: { userId: user.id, plan: chosen.key },
  });

  return NextResponse.json({ url: session.url });
}
