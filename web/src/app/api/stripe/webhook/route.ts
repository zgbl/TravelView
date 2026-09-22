import { NextResponse } from 'next/server';
import { stripe } from '@/lib/stripe';
import { grantForCheckout } from '@/lib/grant';
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

  if (event.type === 'checkout.session.completed') {
    const s = event.data.object;
    const userId = s.metadata?.userId;
    if (userId) {
      // 幂等和发放逻辑都在 grantForCheckout 里 ——
      // 和"支付成功跳回来"那条路共用同一份，两处不会算出不同的额度
      await grantForCheckout({
        userId,
        eventId: event.id,
        eventType: event.type,
        plan: s.metadata?.plan,
        sessionId: s.id,
        paymentIntent: typeof s.payment_intent === 'string'
          ? s.payment_intent : null,
        amountCents: s.amount_total,
        currency: s.currency,
      });
    }
  }

  // 续费成功、被暂停、过期，都从这一个事件走 ——
  // 以 Stripe 的账期为准，不要自己算一年后是哪天
  if (event.type === 'customer.subscription.updated' ||
      event.type === 'customer.subscription.created') {
    const sub = event.data.object as any;
    /**
     * 账期字段在**两个地方**，都要认。
     *
     * Stripe 从 2025-03-31.basil 起把 current_period_end 从 Subscription 顶层
     * 挪到了 subscription item 上。而 webhook 的 payload 是按**端点配置的
     * API 版本**渲染的 —— 端点用 dahlia 就只在 items[0] 里，用 acacia 才在顶层。
     * 同一个应用的本地/测试/线上可能各配各的，所以不能只读一个位置。
     *
     * 只看顶层会拿到 undefined，把 subscription_until 写成 NULL，
     * 而 entitlementOf() 把 NULL 当成"永不过期" —— 等于白送。
     */
    const periodEnd = sub.current_period_end ??
      sub.items?.data?.[0]?.current_period_end;

    if (periodEnd) {
      const until = new Date(periodEnd * 1000).toISOString();
      await one(
        `update users set subscription_status = $2, subscription_until = $3
           where stripe_customer_id = $1`,
        [String(sub.customer), String(sub.status), until],
      );
    } else {
      // 两个位置都没有: 说明字段名又变了。**这时绝不能写 NULL** ——
      // 保留旧的到期时间，最坏是沿用上一期，好过变成永久免费。
      // 只更新状态，并把这件事喊出来，别让它静默发生。
      console.error(
        '[stripe webhook] 取不到账期，subscription_until 保持不变', {
          eventId: event.id, type: event.type,
          customer: sub.customer, status: sub.status,
        });
      await one(
        `update users set subscription_status = $2 where stripe_customer_id = $1`,
        [String(sub.customer), String(sub.status)],
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
