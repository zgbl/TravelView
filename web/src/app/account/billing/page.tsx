import Link from 'next/link';
import { redirect } from 'next/navigation';
import { requireUser } from '@/lib/auth';
import { one, query } from '@/lib/db';
import { betaState } from '@/lib/access';
import { CREDIT_PLANS, SUBSCRIPTION_PLANS, stripeStatus } from '@/lib/stripe';
import { reconcileCheckout } from '@/lib/reconcile';
import { getLocale } from '@/lib/i18n.server';
import { href, t } from '@/lib/i18n';
import CheckoutButtons from '@/components/CheckoutButtons';
import BillingPortalButton from '@/components/BillingPortalButton';

export const dynamic = 'force-dynamic';

/**
 * 付费页（登录后）。
 *
 * 和 /pricing 的分工: /pricing 是给还没注册的人看的**广告页**，
 * 这一页是**已登录用户真正掏钱和管订阅的地方** —— 当前权益、买、管理、票据，
 * 全在一屏里。
 *
 * 一个刻意的决定: **公测期也照样让人买。**
 * 免费期把付费入口藏起来，等于主动放弃那些"现在就愿意付钱"的人，
 * 而这批人正是最该被拿到的早期信号。买到的额度不过期、公测期也不消耗。
 *
 * 所有文案走 t() —— 这个站是中英双语的，写死中文等于把英文用户挡在付款之前。
 */
export default async function Billing({
  searchParams,
}: {
  searchParams: Promise<{ checkout?: string }>;
}) {
  const user = await requireUser();
  if (!user) redirect('/login?next=/account/billing');

  const L = await getLocale();

  // 刚从 Stripe 付完款跳回来: 先跟 Stripe 对一次账再读库，
  // 否则用户看到的是发放前的旧数字。发放是幂等的，刷新多少次都只加一次。
  const { checkout } = await searchParams;
  const justPaid = !!checkout;
  if (checkout) await reconcileCheckout(checkout, user.id);

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
    livemode: boolean;
    amount_cents: number | null;
    currency: string | null;
    status: string;
    created_at: string;
  };
  // credits_granted 是 006 迁移加的列。迁移还没跑就整页 500 太蠢了 ——
  // 付款记录是这一页最不重要的部分，查不到就当没有，别拖垮"能不能付钱"。
  let payments: Payment[] = [];
  try {
    payments = await query<Payment>(
      `select kind, coalesce(credits_granted, 0) as credits_granted,
              coalesce(livemode, false) as livemode,
              amount_cents, currency, status, created_at
         from payments where user_id = $1
        order by created_at desc limit 10`, [user.id]);
  } catch {
    try {
      const rows = await query<Omit<Payment, 'credits_granted' | 'livemode'>>(
        `select kind, amount_cents, currency, status, created_at
           from payments where user_id = $1
          order by created_at desc limit 10`, [user.id]);
      payments = rows.map((r) => ({ ...r, credits_granted: 0, livemode: true }));
    } catch {
      payments = [];
    }
  }

  const beta = await betaState();
  const stripe = stripeStatus();
  const subscribed = row?.subscription_status === 'active';
  const credits = row?.story_credits ?? 0;

  const plans = [
    ...SUBSCRIPTION_PLANS.map((p) => ({
      key: p.key,
      name: t(L, `plan.${p.key}.name`),
      priceLabel: p.priceLabel,
      blurb: t(L, `plan.${p.key}.blurb`),
      available: !!p.priceId,
      primary: p.key === 'pro_yearly',
    })),
    ...CREDIT_PLANS.map((p) => ({
      key: p.key,
      name: t(L, `plan.${p.key}.name`),
      priceLabel: p.priceLabel,
      blurb: t(L, `plan.${p.key}.blurb`),
      available: !!p.priceId,
    })),
  ];

  return (
    <main className="mx-auto max-w-3xl px-6 py-16">
      <div className="mb-10 flex items-center justify-between">
        <h1 className="text-3xl font-semibold tracking-tight">
          {t(L, 'billing.title')}
        </h1>
        <Link href={href(L, '/account')}
          className="text-sm text-muted hover:text-paper">
          {t(L, 'billing.back')}
        </Link>
      </div>

      {/* 当前权益 —— 第一眼要能回答"我现在能不能发布" */}
      {justPaid && (
        <p className="mb-6 rounded-xl border border-accentBright/40
          bg-accentBright/10 px-5 py-4 text-sm text-accentBright">
          {t(L, 'billing.paid')}
        </p>
      )}

      <section className="rounded-2xl border border-white/12 p-6">
        <div className="text-sm text-muted">{user.email}</div>
        <div className="mt-3 text-lg">
          {subscribed ? (
            <span className="text-accentBright">
              {t(L, 'billing.subscribed')}
              {row?.subscription_until &&
                `（${t(L, 'billing.renews',
                  { date: row.subscription_until.slice(0, 10) })}）`}
            </span>
          ) : (
            <span>
              {t(L, 'billing.credits')}
              <strong>{credits}</strong>
              {t(L, 'billing.credits.unit')}
            </span>
          )}
        </div>
        {subscribed && credits > 0 && (
          <div className="mt-1 text-sm text-muted">
            {t(L, 'billing.credits')}
            <strong className="text-paper">{credits}</strong>
            {t(L, 'billing.credits.unit')}
          </div>
        )}
        {row?.subscription_status === 'past_due' && (
          <p className="mt-2 text-sm text-amber-400">{t(L, 'billing.pastdue')}</p>
        )}
        {beta.free && (
          <p className="mt-3 rounded-xl border border-accentBright/30
            bg-accentBright/5 px-4 py-3 text-sm text-muted">
            <strong className="text-accentBright">
              {t(L, 'billing.beta.title')}
            </strong>
            {t(L, 'billing.beta.body', { limit: beta.limit })}
          </p>
        )}
        {row?.stripe_customer_id && (
          <div className="mt-5">
            <BillingPortalButton
              label={t(L, 'billing.portal')}
              busyLabel={t(L, 'billing.portal.busy')}
              errLabel={t(L, 'billing.portal.err')}
            />
          </div>
        )}
      </section>

      {/* 买 */}
      <section className="mt-10">
        <h2 className="text-xl font-semibold">
          {subscribed ? t(L, 'billing.topup') : t(L, 'billing.choose')}
        </h2>
        <p className="mt-2 text-sm text-muted">{t(L, 'billing.choose.sub')}</p>

        <div className="mt-6 grid gap-4 md:grid-cols-2">
          <div className="rounded-2xl border border-accentBright/40
            bg-accentBright/5 p-6">
            <h3 className="font-semibold">{t(L, 'billing.pro.title')}</h3>
            <p className="mt-1 text-2xl font-semibold tracking-tight">
              $50
              <span className="text-sm font-normal text-muted">
                {t(L, 'billing.pro.per.year')}
              </span>
            </p>
            <p className="mt-1 text-xs text-muted">{t(L, 'billing.pro.alt')}</p>
          </div>
          <div className="rounded-2xl border border-white/12 p-6">
            <h3 className="font-semibold">{t(L, 'billing.packs.title')}</h3>
            <ul className="mt-2 space-y-1 text-sm text-muted">
              <li>{t(L, 'billing.packs.5')}</li>
              <li>{t(L, 'billing.packs.10')}</li>
              <li>{t(L, 'billing.packs.25')}</li>
            </ul>
          </div>
        </div>

        {stripe.ready ? (
          <CheckoutButtons
            plans={plans}
            busyLabel={t(L, 'checkout.busy')}
            errLabel={t(L, 'checkout.err')}
            loginPath={href(L, '/login')}
          />
        ) : (
          <p className="mt-6 rounded-xl border border-white/12 px-4 py-3
            text-sm text-muted">
            {t(L, 'billing.notready')}
          </p>
        )}
        {!stripe.livemode && stripe.ready && (
          <p className="mt-3 text-xs text-amber-400">{t(L, 'billing.testmode')}</p>
        )}
      </section>

      {/* 票据 */}
      {payments.length > 0 && (
        <section className="mt-12">
          <h2 className="text-sm font-medium">{t(L, 'billing.history')}</h2>
          <table className="mt-3 w-full text-sm">
            <tbody>
              {payments.map((p, i) => (
                <tr key={i} className="border-t border-white/10">
                  <td className="py-2 text-muted">
                    {String(p.created_at).slice(0, 10)}
                  </td>
                  <td className="py-2">
                    {t(L, `plan.${p.kind}.name`)}
                    {p.credits_granted > 0 && (
                      <span className="ml-2 text-muted">
                        {t(L, 'billing.granted', { n: p.credits_granted })}
                      </span>
                    )}
                  </td>
                  <td className="py-2 text-right">
                    {p.amount_cents != null
                      ? `$${(p.amount_cents / 100).toFixed(2)}`
                      : '—'}
                  </td>
                  <td className="py-2 text-right text-muted">
                    {p.status}
                    {!p.livemode && (
                      <span className="ml-2 rounded bg-amber-400/15 px-1.5
                        py-0.5 text-[10px] text-amber-400">TEST</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <p className="mt-3 text-xs text-muted">{t(L, 'billing.history.note')}</p>
        </section>
      )}

      <p className="mt-12 text-xs text-muted">{t(L, 'billing.privacy')}</p>
    </main>
  );
}
