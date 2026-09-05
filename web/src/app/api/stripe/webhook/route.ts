import { NextResponse } from 'next/server';
import { stripe } from '@/lib/stripe';
import { one } from '@/lib/db';

/**
 * Stripe webhook —— **权益只在这里发放**。
 *
 * 绝不能在前端"支付成功跳转"里发权益: 那条路径可以被直接访问。
 * 支付的唯一真相是 Stripe 签名过的这个回调。
 */
export async function POST(req: Request) {
  const sig = req.headers.get('stripe-signature');
  const raw = await req.text();
  if (!sig) return NextResponse.json({ error: 'no signature' }, { status: 400 });

  let event;
  try {
    event = stripe.webhooks.constructEvent(
      raw, sig, process.env.STRIPE_WEBHOOK_SECRET ?? '',
    );
  } catch (e) {
    return NextResponse.json({ error: `签名校验失败: ${e}` }, { status: 400 });
  }

  if (event.type === 'checkout.session.completed') {
    const s = event.data.object;
    const userId = s.metadata?.userId;
    const plan = s.metadata?.plan;
    if (userId) {
      if (plan === 'subscription') {
        await one(
          `update users set subscription_status = 'active',
             subscription_until = now() + interval '1 year' where id = $1`,
          [userId],
        );
      } else {
        await one(
          'update users set story_credits = story_credits + 1 where id = $1',
          [userId],
        );
      }
      await one(
        `insert into payments
           (user_id, stripe_session_id, stripe_payment_intent, kind,
            amount_cents, currency, status)
         values ($1,$2,$3,$4,$5,$6,$7)
         on conflict (stripe_session_id) do nothing`,
        [userId, s.id, String(s.payment_intent ?? ''), plan ?? 'onetime',
         s.amount_total, s.currency, 'paid'],
      );
    }
  }

  if (event.type === 'customer.subscription.deleted') {
    const sub = event.data.object;
    await one(
      `update users set subscription_status = 'canceled'
         where stripe_customer_id = $1`,
      [String(sub.customer)],
    );
  }

  return NextResponse.json({ received: true });
}
