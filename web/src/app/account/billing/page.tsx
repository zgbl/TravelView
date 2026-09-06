import Link from 'next/link';
import { redirect } from 'next/navigation';
import { requireUser } from '@/lib/auth';
import { one, query } from '@/lib/db';
import { getLocale } from '@/lib/i18n.server';
import { href } from '@/lib/i18n';
import { betaState } from '@/lib/access';
import { CREDIT_PLANS, SUBSCRIPTION_PLANS, stripeStatus } from '@/lib/stripe';
import CheckoutButtons from '@/components/CheckoutButtons';
import BillingPortalButton from '@/components/BillingPortalButton';

export const dynamic = 'force-dynamic';

/**
 * 付费页（登录后）。
 *
 * 和 /pricing 的分工: /pricing 是给还没注册的人看的**广告页**，
 * 这一页是**已登录用户真正掏钱和管订阅的地方** —— 当前权益、买、管理、票据，
 * 全在一屏里。之前缺的就是这一页: 注册完了没有任何入口能付钱。
 *
 * 一个刻意的决定: **公测期也照样让人买。**
 * 免费期把付费入口藏起来，等于主动放弃了那些"现在就愿意付钱"的人，
 * 而这批人正是最该被拿到的早期信号。买到的额度不过期、公测期也不消耗。
 */
export default async function Billing() {
  const user = await requireUser();
  if (!user) redirect('/login?next=/account/billing');

  const row = await one<{
    story_credits: number;
    subscription_status: string | null;
    subscription_until: string | null;
    stripe_customer_id: string | null;
  }>(`select story_credits, subscription_status, subscription_until,
             stripe_customer_id
        from users where id = $1`, [user.id]);

  type Payment = {
    kind: string;
    credits_granted: number;
    amount_cents: number | null;
    currency: string | null;
    status: string;
    created_at: string;
  };
  // credits_granted 是 006 迁移加的列。迁移还没跑就整页 500 太蠢了 ——
  // 付款记录是这一页最不重要的部分，查不到就当没有，别拖垮"能不能付钱"这件事。
  let payments: Payment[] = [];
  try {
    payments = await query<Payment>(
      `select kind, coalesce(credits_granted, 0) as credits_granted,
              amount_cents, currency, status, created_at
         from payments where user_id = $1
        order by created_at desc limit 10`, [user.id]);
  } catch {
    try {
      const rows = await query<Omit<Payment, 'credits_granted'>>(
        `select kind, amount_cents, currency, status, created_at
           from payments where user_id = $1
          order by created_at desc limit 10`, [user.id]);
      payments = rows.map((r) => ({ ...r, credits_granted: 0 }));
    } catch {
      payments = [];
    }
  }

  const L = await getLocale();
  const beta = await betaState();
  const stripe = stripeStatus();
  const subscribed = row?.subscription_status === 'active';
  const credits = row?.story_credits ?? 0;

  const plans = [
    ...SUBSCRIPTION_PLANS.map((p) => ({
      key: p.key, name: p.name, priceLabel: p.priceLabel, blurb: p.blurb,
      available: !!p.priceId, primary: p.key === 'pro_yearly',
    })),
    ...CREDIT_PLANS.map((p) => ({
      key: p.key, name: p.name, priceLabel: p.priceLabel, blurb: p.blurb,
      available: !!p.priceId,
    })),
  ];

  return (
    <main className="mx-auto max-w-3xl px-6 py-16">
      <div className="mb-10 flex items-center justify-between">
        <h1 className="text-3xl font-semibold tracking-tight">订阅与额度</h1>
        <Link href={href(L, '/account')} className="text-sm text-muted hover:text-paper">
          返回账户
        </Link>
      </div>

      {/* 当前权益 —— 第一眼要能回答"我现在能不能发布" */}
      <section className="rounded-2xl border border-white/12 p-6">
        <div className="text-sm text-muted">{user.email}</div>
        <div className="mt-3 text-lg">
          {subscribed ? (
            <span className="text-accentBright">
              Pro 订阅中，不限篇数
              {row?.subscription_until &&
                `（下次续费 ${row.subscription_until.slice(0, 10)}）`}
            </span>
          ) : (
            <span>
              可发布额度：<strong>{credits}</strong> 篇
            </span>
          )}
        </div>
        {row?.subscription_status === 'past_due' && (
          <p className="mt-2 text-sm text-amber-400">
            上次扣款没成功（多半是卡过期）。权益到期前还能用，去下面的
            「管理订阅」换张卡就行。
          </p>
        )}
        {beta.free && (
          <p className="mt-3 rounded-xl border border-accentBright/30
            bg-accentBright/5 px-4 py-3 text-sm text-muted">
            <strong className="text-accentBright">公测期发布免费</strong>
            ，现在发布不扣额度。你买的额度会一直留着，
            公测结束（注册满 {beta.limit} 人）后才开始消耗。
          </p>
        )}
        {row?.stripe_customer_id && (
          <div className="mt-5">
            <BillingPortalButton label="管理订阅 / 发票 / 换卡" />
          </div>
        )}
      </section>

      {/* 买 */}
      <section className="mt-10">
        <h2 className="text-xl font-semibold">
          {subscribed ? '加买额度' : '选一个方案'}
        </h2>
        <p className="mt-2 text-sm text-muted">
          Pro 订阅不限篇数；不想订阅就按篇买，额度不过期，和订阅可以并存。
        </p>

        <div className="mt-6 grid gap-4 md:grid-cols-2">
          <div className="rounded-2xl border border-accentBright/40
            bg-accentBright/5 p-6">
            <h3 className="font-semibold">Pro · 不限篇数</h3>
            <p className="mt-1 text-2xl font-semibold tracking-tight">
              $50<span className="text-sm font-normal text-muted"> / 年</span>
            </p>
            <p className="mt-1 text-xs text-muted">或 $8 / 月，随时取消</p>
          </div>
          <div className="rounded-2xl border border-white/12 p-6">
            <h3 className="font-semibold">额度包 · 按篇买</h3>
            <ul className="mt-2 space-y-1 text-sm text-muted">
              <li>$5 = 2 篇（$2.5 一篇）</li>
              <li>$10 = 5 篇（$2 一篇）</li>
              <li>$25 = 15 篇（$1.67 一篇）</li>
            </ul>
          </div>
        </div>

        {stripe.ready ? (
          <CheckoutButtons plans={plans} />
        ) : (
          <p className="mt-6 rounded-xl border border-white/12 px-4 py-3
            text-sm text-muted">
            支付还没开通，公测期间发布本来就是免费的。
          </p>
        )}
        {!stripe.livemode && stripe.ready && (
          <p className="mt-3 text-xs text-amber-400">
            当前是 Stripe 测试模式，不会真的扣款。测试卡号 4242 4242 4242 4242，
            有效期填未来任意日期，CVC 任意三位。
          </p>
        )}
      </section>

      {/* 票据 */}
      {payments.length > 0 && (
        <section className="mt-12">
          <h2 className="text-sm font-medium">付款记录</h2>
          <table className="mt-3 w-full text-sm">
            <tbody>
              {payments.map((p, i) => (
                <tr key={i} className="border-t border-white/10">
                  <td className="py-2 text-muted">
                    {String(p.created_at).slice(0, 10)}
                  </td>
                  <td className="py-2">
                    {p.kind}
                    {p.credits_granted > 0 && (
                      <span className="ml-2 text-muted">
                        +{p.credits_granted} 篇
                      </span>
                    )}
                  </td>
                  <td className="py-2 text-right">
                    {p.amount_cents != null
                      ? `$${(p.amount_cents / 100).toFixed(2)}`
                      : '—'}
                  </td>
                  <td className="py-2 text-right text-muted">{p.status}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <p className="mt-3 text-xs text-muted">
            正式发票和退款在「管理订阅」里的 Stripe 门户处理。
          </p>
        </section>
      )}

      <p className="mt-12 text-xs text-muted">
        无论哪一档，原图都不会上传。服务器上只有你挑中的那些照片的压缩版本。
      </p>
    </main>
  );
}
