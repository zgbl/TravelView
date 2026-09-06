import Stripe from 'stripe';

// 不锁死 apiVersion: 不同版本的 stripe SDK 各自带一个类型上允许的版本，
// 写死旧版本会在 npm install 之后构建报类型错。缺省时 SDK 用自己的默认版本。
export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY ?? '');

const env = (k: string) => (process.env[k] ?? '').trim() || undefined;

/**
 * 定价分两类，对应 Stripe 里同一个 product 下的 5 条 price:
 *
 *   订阅 Pro   —— 不限篇数。月付 $8 / 年付 $50（年付相当于 5.2 折）
 *   额度包     —— 一次付费买"能发布几篇"的额度，不想订阅的人用。
 *                 $5=1 篇 / $10=3 篇 / $25=10 篇（越买越便宜，制造往上买的动机）
 *
 * 额度和订阅是并存的: 订阅期内不消耗额度，退订后额度还在。
 * 改单价只在 Stripe 后台建新 price 换 ID，改"一次给几篇"只改这里的 credits。
 */
export const PLANS = {
  pro_yearly: {
    key: 'pro_yearly',
    priceId: env('STRIPE_PRICE_PRO_YEARLY') ?? env('STRIPE_PRICE_SUBSCRIPTION'),
    mode: 'subscription' as const,
    name: 'Pro · 年付',
    priceLabel: '$50 / 年',
    blurb: '不限篇数，平均 $4.17/月',
    credits: 0,
  },
  pro_monthly: {
    key: 'pro_monthly',
    priceId: env('STRIPE_PRICE_PRO_MONTHLY'),
    mode: 'subscription' as const,
    name: 'Pro · 月付',
    priceLabel: '$8 / 月',
    blurb: '不限篇数，随时取消',
    credits: 0,
  },
  credits_1: {
    key: 'credits_1',
    priceId: env('STRIPE_PRICE_CREDITS_5') ?? env('STRIPE_PRICE_ONETIME'),
    mode: 'payment' as const,
    name: '1 篇额度',
    priceLabel: '$5',
    blurb: '先发一篇试试',
    credits: 1,
  },
  credits_3: {
    key: 'credits_3',
    priceId: env('STRIPE_PRICE_CREDITS_10'),
    mode: 'payment' as const,
    name: '3 篇额度',
    priceLabel: '$10',
    blurb: '$3.33 一篇',
    credits: 3,
  },
  credits_10: {
    key: 'credits_10',
    priceId: env('STRIPE_PRICE_CREDITS_25'),
    mode: 'payment' as const,
    name: '10 篇额度',
    priceLabel: '$25',
    blurb: '$2.5 一篇，最划算',
    credits: 10,
  },
} as const;

export type PlanKey = keyof typeof PLANS;

/** 旧客户端/旧链接里的 plan 名，映射到现在的档位，别让已发出去的按钮失效 */
const LEGACY: Record<string, PlanKey> = {
  onetime: 'credits_1',
  subscription: 'pro_yearly',
};

export function resolvePlan(plan?: string) {
  if (!plan) return undefined;
  const key = (plan in PLANS ? plan : LEGACY[plan]) as PlanKey | undefined;
  return key ? PLANS[key] : undefined;
}

/** 这一档一次性付款该发多少篇额度。webhook 用它，别在两处各写一份数字。 */
export function creditsForPlan(plan?: string) {
  return resolvePlan(plan)?.credits ?? 0;
}

/** 展示顺序: 订阅在前（我们希望人选这个），额度包在后 */
export const SUBSCRIPTION_PLANS = [PLANS.pro_yearly, PLANS.pro_monthly];
export const CREDIT_PLANS = [PLANS.credits_1, PLANS.credits_3, PLANS.credits_10];

/**
 * Stripe 到底配没配好。
 *
 * 密钥是环境变量，不是数据库里的设置 —— **不做"在后台网页里填密钥"那种功能**:
 * 一个能读写支付密钥的网页表单，本身就是最值钱的攻击目标，
 * 而且密钥写进数据库后备份、日志、截图到处都是它。
 * 后台只**显示**配没配好，填还是去 /etc/travelview/env。
 */
export function stripeStatus() {
  const secret = env('STRIPE_SECRET_KEY') ?? '';
  const checks = {
    secretKey: !!secret,
    livemode: secret.startsWith('sk_live_'),
    webhookSecret: !!env('STRIPE_WEBHOOK_SECRET'),
    priceProYearly: !!PLANS.pro_yearly.priceId,
    priceProMonthly: !!PLANS.pro_monthly.priceId,
    priceCredits1: !!PLANS.credits_1.priceId,
    priceCredits3: !!PLANS.credits_3.priceId,
    priceCredits10: !!PLANS.credits_10.priceId,
  };
  return {
    ...checks,
    // 收一次钱最少需要这三样
    ready: checks.secretKey && checks.webhookSecret &&
      (checks.priceCredits1 || checks.priceProYearly || checks.priceProMonthly),
  };
}
