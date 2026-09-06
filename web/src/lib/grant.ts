import { one } from './db';
import { creditsForPlan, resolvePlan, stripeMode } from './stripe';

/**
 * 发权益。**webhook 和"支付成功跳回来"两条路都走这一份代码。**
 *
 * 为什么要两条路: webhook 是唯一可信的真相源，但它**不保证及时**——
 * 沙盒里没配端点、防火墙挡了、服务重启、Stripe 重试排队，
 * 都会让用户付完钱回到网站看见"额度 0"。那一刻用户不会想"可能是 webhook 延迟"，
 * 他只会觉得钱被吞了。所以跳回来时我们自己去 Stripe 查一次会话，
 * 查到 paid 就地发放；webhook 后到也没关系，下面的幂等键挡住重复发放。
 *
 * 幂等键是 stripe_events.id。webhook 用事件 id，这里用 `session:<cs_id>`，
 * 两者都指向同一笔付款，谁先到谁发，另一个自然落空。
 */
export type GrantInput = {
  userId: string;
  /** 幂等键: webhook 传 event.id，回跳传 `session:<cs_id>` */
  eventId: string;
  eventType: string;
  plan?: string | null;
  sessionId: string;
  paymentIntent?: string | null;
  amountCents?: number | null;
  currency?: string | null;
};

export async function grantForCheckout(g: GrantInput) {
  // 幂等: Stripe 会重发，回跳也可能被刷新好几次。
  // 没有这道闸，一次付款可能加两次额度。
  try {
    const fresh = await one<{ id: string }>(
      `insert into stripe_events (id, type) values ($1, $2)
       on conflict (id) do nothing returning id`,
      [g.eventId, g.eventType]);
    if (!fresh) return { applied: false, credits: 0 };
  } catch {
    // 幂等表还没建（迁移没跑）时不阻断发放 —— 宁可重复也不能吞掉付款，
    // 重复了还能人工退，吞了用户是真花了钱没拿到东西
  }

  const plan = g.plan ?? undefined;
  let credits = 0;

  if (resolvePlan(plan)?.mode === 'subscription') {
    // 先给一个保底到期时间，真正的到期日以随后的
    // customer.subscription.* 事件里的 current_period_end 为准
    const span = plan === 'pro_monthly' ? '1 month' : '1 year';
    await one(
      `update users set subscription_status = 'active',
         subscription_until = now() + $2::interval where id = $1`,
      [g.userId, span]);
  } else {
    // 一次给几篇由档位决定（$5=2 / $10=5 / $25=15）。
    // 认不出的 plan 保底给 1 篇 —— 用户真付了钱，宁可多给也不能不给
    credits = creditsForPlan(plan) || 1;
    await one(
      'update users set story_credits = story_credits + $2 where id = $1',
      [g.userId, credits]);
  }

  const row = [g.userId, g.sessionId, String(g.paymentIntent ?? ''),
    plan ?? 'credits_2', g.amountCents ?? null, g.currency ?? null, 'paid'];
  // 记下这笔是不是正式模式产生的。测试和生产共用一个数据库时，
  // 这一列是事后唯一能把测试单据挑出来的依据
  const livemode = stripeMode() === 'live';
  try {
    await one(
      `insert into payments
         (user_id, stripe_session_id, stripe_payment_intent, kind,
          amount_cents, currency, status, credits_granted, livemode)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9)
       on conflict (stripe_session_id) do nothing`,
      [...row, credits, livemode]);
  } catch {
    // 006 迁移还没跑（没有 credits_granted 列）时退回旧写法。
    // 额度已经发出去了，这里只是记账，绝不能因为少一列就整个 500 ——
    // webhook 返 500 会让 Stripe 反复重试同一笔
    await one(
      `insert into payments
         (user_id, stripe_session_id, stripe_payment_intent, kind,
          amount_cents, currency, status)
       values ($1,$2,$3,$4,$5,$6,$7)
       on conflict (stripe_session_id) do nothing`,
      row);
  }

  return { applied: true, credits };
}
