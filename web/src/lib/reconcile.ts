import { stripe, stripeStatus } from './stripe';
import { grantForCheckout } from './grant';

/**
 * 支付成功跳回来时，主动跟 Stripe 对一次账。
 *
 * 这是"付了钱页面没反应"的兜底。**不信任 URL 里的任何东西**:
 * session_id 是公开可见的，所以这里重新去 Stripe 取一遍会话，
 * 核对 payment_status 和 client_reference_id 是不是当前登录的这个人，
 * 都对得上才发权益。发放本身是幂等的，webhook 随后到达不会重复加。
 */
export async function reconcileCheckout(sessionId: string, userId: string) {
  if (!sessionId.startsWith('cs_') || !stripeStatus().secretKey) return false;

  try {
    const s = await stripe.checkout.sessions.retrieve(sessionId);
    const paid = s.payment_status === 'paid' || s.status === 'complete';
    const owner = s.client_reference_id ?? s.metadata?.userId;
    if (!paid || owner !== userId) return false;

    const res = await grantForCheckout({
      userId,
      eventId: `session:${s.id}`,
      eventType: 'checkout.session.reconciled',
      plan: s.metadata?.plan,
      sessionId: s.id,
      paymentIntent: typeof s.payment_intent === 'string' ? s.payment_intent : null,
      amountCents: s.amount_total,
      currency: s.currency,
    });
    return res.applied;
  } catch {
    // 对账失败不该让页面挂 —— webhook 还是会把权益补上
    return false;
  }
}
