import Stripe from 'stripe';

// 不锁死 apiVersion: 不同版本的 stripe SDK 各自带一个类型上允许的版本，
// 写死旧版本会在 npm install 之后构建报类型错。缺省时 SDK 用自己的默认版本。
export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY ?? '');

/**
 * 定价刻意只有两档，而且都指向同一件事: **能发布一篇 Story**。
 *
 * 不做积分、等级、套餐 —— 第一版要验证的是"有没有人愿意为发布付钱"，
 * 不是"哪种套餐卖得好"。表结构留了扩展余地，改定价不用改数据库。
 */
export const PLANS = {
  onetime: {
    key: 'onetime',
    priceId: process.env.STRIPE_PRICE_ONETIME,
    mode: 'payment' as const,
    name: 'Publish one story',
    blurb: '发布一篇旅行故事，永久有效的公开链接',
    grants: { credits: 1 },
  },
  subscription: {
    key: 'subscription',
    priceId: process.env.STRIPE_PRICE_SUBSCRIPTION,
    mode: 'subscription' as const,
    name: 'Unlimited',
    blurb: '一年内不限篇数',
    grants: { subscription: true },
  },
} as const;

export type PlanKey = keyof typeof PLANS;

/**
 * Stripe 到底配没配好。
 *
 * 密钥是环境变量，不是数据库里的设置 —— **不做"在后台网页里填密钥"那种功能**:
 * 一个能读写支付密钥的网页表单，本身就是最值钱的攻击目标，
 * 而且密钥写进数据库后备份、日志、截图到处都是它。
 * 后台只**显示**配没配好，填还是去 /etc/travelview/env。
 */
export function stripeStatus() {
  const v = (k: string) => (process.env[k] ?? '').trim();
  const secret = v('STRIPE_SECRET_KEY');
  const checks = {
    secretKey: !!secret,
    livemode: secret.startsWith('sk_live_'),
    webhookSecret: !!v('STRIPE_WEBHOOK_SECRET'),
    priceOnetime: !!v('STRIPE_PRICE_ONETIME'),
    priceSubscription: !!v('STRIPE_PRICE_SUBSCRIPTION'),
  };
  return {
    ...checks,
    // 收一次钱最少需要这三样
    ready: checks.secretKey && checks.webhookSecret && checks.priceOnetime,
  };
}
