import { NextResponse } from 'next/server';
import { creditsForPlan, resolvePlan, stripe } from '@/lib/stripe';
import { one } from '@/lib/db';

// 必须跑在 Node 运行时: 验签要原始请求体，Edge 上拿不到
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

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
    // 400 让 Stripe 不再重试这一条 —— 签名错了重试多少次都一样
    return NextResponse.json({ error: `签名校验失败: ${e}` }, { status: 400 });
  }

  // 幂等: Stripe 会重发（超时、5xx、它自己的重试）。
  // 没有这道闸，一次付款可能加两次额度。
  try {
    const fresh = await one<{ id: string }>(
      `insert into stripe_events (id, type) values ($1, $2)
       on conflict (id) do nothing returning id`,
      [event.id, event.type]);
    if (!fresh) return NextResponse.json({ received: true, duplicate: true });
  } catch {
    // 幂等表还没建（迁移没跑）时不阻断发放 —— 宁可重复也不能吞掉付款，
    // 重复了还能人工退，吞了用户是真花了钱没拿到东西
  }

  if (event.type === 'checkout.session.completed') {
    const s = event.data.object;
    const userId = s.metadata?.userId;
    const plan = s.metadata?.plan;
    if (userId) {
      // 订阅: 先给一个保底到期时间，真正的到期日以随后的
      // customer.subscription.* 事件里的 current_period_end 为准
      if (resolvePlan(plan)?.mode === 'subscription') {
        const span = plan === 'pro_monthly' ? '1 month' : '1 year';
        await one(
          `update users set subscription_status = 'active',
             subscription_until = now() + $2::interval where id = $1`,
          [userId, span],
        );
      } else {
        // 一次给几篇由档位决定（$5=1 / $10=3 / $25=10）。
        // 认不出的 plan 保底给 1 篇 —— 用户真付了钱，宁可多给也不能不给
        const credits = creditsForPlan(plan) || 1;
        await one(
          'update users set story_credits = story_credits + $2 where id = $1',
          [userId, credits],
        );
      }
      await one(
        `insert into payments
           (user_id, stripe_session_id, stripe_payment_intent, kind,
            amount_cents, currency, status)
         values ($1,$2,$3,$4,$5,$6,$7)
         on conflict (stripe_session_id) do nothing`,
        [userId, s.id, String(s.payment_intent ?? ''), plan ?? 'credits_1',
         s.amount_total, s.currency, 'paid'],
      );
    }
  }

  // 续费成功、被暂停、过期，都从这一个事件走 ——
  // 以 Stripe 的 current_period_end 为准，不要自己算一年后是哪天
  if (event.type === 'customer.subscription.updated' ||
      event.type === 'customer.subscription.created') {
    const sub = event.data.object as any;
    const until = sub.current_period_end
      ? new Date(sub.current_period_end * 1000).toISOString()
      : null;
    await one(
      `update users set subscription_status = $2, subscription_until = $3
         where stripe_customer_id = $1`,
      [String(sub.customer), String(sub.status), until],
    );
  }

  if (event.type === 'customer.subscription.deleted') {
    const sub = event.data.object;
    await one(
      `update users set subscription_status = 'canceled'
         where stripe_customer_id = $1`,
      [String(sub.customer)],
    );
  }

  // 扣款失败: 不立刻停权益（可能只是卡过期），标记出来，
  // 到期时间一到自然失效。粗暴断服会把本来愿意换张卡的用户赶走。
  if (event.type === 'invoice.payment_failed') {
    const inv = event.data.object as any;
    await one(
      `update users set subscription_status = 'past_due'
         where stripe_customer_id = $1`,
      [String(inv.customer)]);
  }

  return NextResponse.json({ received: true });
}
