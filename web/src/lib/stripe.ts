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
  credits_2: {
    key: 'credits_2',
    priceId: env('STRIPE_PRICE_CREDITS_5') ?? env('STRIPE_PRICE_ONETIME'),
    mode: 'payment' as const,
    name: '2 篇额度',
    priceLabel: '$5',
    blurb: '$2.5 一篇，先试试',
    credits: 2,
  },
  credits_5: {
    key: 'credits_5',
    priceId: env('STRIPE_PRICE_CREDITS_10'),
    mode: 'payment' as const,
    name: '5 篇额度',
    priceLabel: '$10',
    blurb: '$2 一篇',
    credits: 5,
  },
  credits_15: {
    key: 'credits_15',
    priceId: env('STRIPE_PRICE_CREDITS_25'),
    mode: 'payment' as const,
    name: '15 篇额度',
    priceLabel: '$25',
    blurb: '$1.67 一篇，最划算',
    credits: 15,
  },
} as const;

export type PlanKey = keyof typeof PLANS;

/** 旧客户端/旧链接里的 plan 名，映射到现在的档位，别让已发出去的按钮失效 */
const LEGACY: Record<string, PlanKey> = {
  onetime: 'credits_2',
  credits_1: 'credits_2',
  credits_3: 'credits_5',
  credits_10: 'credits_15',
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
export const CREDIT_PLANS = [PLANS.credits_2, PLANS.credits_5, PLANS.credits_15];

/**
 * 站点地址。Checkout 的回跳、客户门户的 return_url 全都从这里取。
 *
 * **不允许写死域名**: 本地是 localhost:3000、测试机是另一个域名、
 * 线上是正式域名，写死任何一个都意味着另外两个环境的付款流程是坏的。
 * 缺这个变量时直接抛错，比让用户跳到 "undefined/account/billing" 强。
 */
export function siteUrl() {
  const site = (process.env.NEXT_PUBLIC_SITE_URL ?? '').trim()
    .replace(/\/+$/, '');
  if (!site) throw new Error('NEXT_PUBLIC_SITE_URL 没配');
  return site;
}

export type StripeMode = 'live' | 'test' | 'unset';

/** 当前跑在哪个 Stripe 模式下 —— 只看密钥前缀，不需要联网 */
export function stripeMode(): StripeMode {
  const k = (process.env.STRIPE_SECRET_KEY ?? '').trim();
  if (k.startsWith('sk_live_') || k.startsWith('rk_live_')) return 'live';
  if (k.startsWith('sk_test_') || k.startsWith('rk_test_')) return 'test';
  return 'unset';
}

/**
 * Stripe 到底配没配好。
 *
 * 密钥是环境变量，不是数据库里的设置 —— **不做"在后台网页里填密钥"那种功能**:
 * 一个能读写支付密钥的网页表单，本身就是最值钱的攻击目标，
 * 而且密钥写进数据库后备份、日志、截图到处都是它。
 * 后台只**显示**配没配好，填还是去 /etc/travelview/env。
 *
 * 切换测试/正式**只改环境变量**: 5 条 price ID + secret key + webhook secret，
 * 代码一行不动。所以这里只做"有没有配"和"是哪个模式"的判断，
 * 不掺任何跟环境绑定的常量。
 */
export function stripeStatus() {
  const secret = env('STRIPE_SECRET_KEY') ?? '';
  const mode = stripeMode();
  const site = (process.env.NEXT_PUBLIC_SITE_URL ?? '').trim();
  const checks = {
    secretKey: !!secret,
    mode,
    livemode: mode === 'live',
    webhookSecret: !!env('STRIPE_WEBHOOK_SECRET'),
    priceProYearly: !!PLANS.pro_yearly.priceId,
    priceProMonthly: !!PLANS.pro_monthly.priceId,
    priceCredits5usd: !!PLANS.credits_2.priceId,
    priceCredits10usd: !!PLANS.credits_5.priceId,
    priceCredits25usd: !!PLANS.credits_15.priceId,
    siteUrl: site,
    // 正式模式下这两条必须成立，否则回跳会把付过款的用户扔到本机
    siteUrlSane: !!site && !site.includes('localhost'),
  };
  return {
    ...checks,
    // 收一次钱最少需要这三样
    ready: checks.secretKey && checks.webhookSecret &&
      (checks.priceCredits5usd || checks.priceProYearly || checks.priceProMonthly),
    // 正式模式还要求域名是真的
    liveReady: mode === 'live' && checks.webhookSecret && checks.siteUrlSane,
  };
}

/**
 * 拿当前这把密钥去 Stripe 核对每条 price 是否真的存在。
 *
 * 这一步能挡住换环境时最常见、也最难查的一类事故:
 * **密钥换成了 live，price ID 还是 test 的那几条。**
 * price ID 字符串本身不带 test/live 标记，光看配置文件永远看不出来，
 * 只有等第一个真实用户点下付款按钮才会 500 —— 那时候钱和口碑都已经损失了。
 *
 * 只在后台页面调用，缓存 60 秒，别让每次刷新都打五个 Stripe 请求。
 */
type PriceCheck = { key: string; priceId?: string; ok: boolean; note: string };
let priceCache: { at: number; mode: StripeMode; rows: PriceCheck[] } | null = null;

export async function verifyPrices(): Promise<PriceCheck[]> {
  const mode = stripeMode();
  if (priceCache && priceCache.mode === mode &&
      Date.now() - priceCache.at < 60_000) {
    return priceCache.rows;
  }
  const rows: PriceCheck[] = [];
  for (const p of [...SUBSCRIPTION_PLANS, ...CREDIT_PLANS]) {
    if (!p.priceId) {
      rows.push({ key: p.key, ok: false, note: '没配' });
      continue;
    }
    try {
      const price = await stripe.prices.retrieve(p.priceId);
      const amount = price.unit_amount != null
        ? `$${(price.unit_amount / 100).toFixed(2)}` : '?';
      const cadence = price.recurring?.interval
        ? `/${price.recurring.interval}` : ' 一次性';
      const wantSub = p.mode === 'subscription';
      const isSub = !!price.recurring;
      rows.push({
        key: p.key,
        priceId: p.priceId,
        ok: price.active && isSub === wantSub,
        note: !price.active ? `${amount}${cadence}（已停用）`
          : isSub !== wantSub
            ? `${amount}${cadence}（类型对不上: 代码里当成${wantSub ? '订阅' : '一次性'}）`
            : `${amount}${cadence}`,
      });
    } catch (e: any) {
      // 最常见的就是这一条: 拿 live 密钥查 test 的 price
      rows.push({
        key: p.key, priceId: p.priceId, ok: false,
        note: e?.code === 'resource_missing'
          ? `这把${mode === 'live' ? '正式' : '测试'}密钥下不存在这条 price`
          : (e?.message ?? '查不到'),
      });
    }
  }
  priceCache = { at: Date.now(), mode, rows };
  return rows;
}
