import Link from 'next/link';
import CheckoutButtons from '@/components/CheckoutButtons';
import { CREDIT_PLANS, SUBSCRIPTION_PLANS } from '@/lib/stripe';
import { betaState } from '@/lib/access';
import { getLocale } from '@/lib/i18n.server';
import { href, t } from '@/lib/i18n';

export const dynamic = 'force-dynamic';

/**
 * 定价页刻意只有两档。
 * 第一版要验证的是"有没有人愿意为发布付钱"，不是"哪种套餐卖得好"。
 */
export default async function Pricing() {
  const beta = await betaState();
  const L = await getLocale();
  return (
    <main className="mx-auto max-w-4xl px-6 py-24">
      <Link href={href(L, '/')} className="text-sm text-muted">&larr; {t(L, 'nav.back')}</Link>
      <h1 className="mt-6 text-4xl font-semibold tracking-tight">{t(L, 'pricing.title')}</h1>
      {beta.free && (
        <div className="mt-6 rounded-xl border border-accentBright/30
          bg-accentBright/5 px-5 py-4 text-sm">
          <strong className="text-accentBright">
            {t(L, 'beta.free.pricing.title')}
          </strong>
          <span className="ml-1 text-muted">{t(L, 'beta.free.pricing.body')}</span>
        </div>
      )}
      <p className="mt-3 max-w-xl text-muted">
        {t(L, 'pricing.intro')}
        <strong className="text-paper">{t(L, 'pricing.intro.strong')}</strong>
      </p>

      <div className="mt-12 grid gap-6 md:grid-cols-2">
        <div className="rounded-2xl border border-accentBright/40 bg-accentBright/5 p-8">
          <h2 className="text-xl font-semibold">{t(L, 'billing.pro.title')}</h2>
          <p className="mt-2 text-3xl font-semibold tracking-tight">
            $50<span className="text-base font-normal text-muted">{t(L, 'billing.pro.per.year')}</span>
          </p>
          <p className="mt-1 text-sm text-muted">{t(L, 'billing.pro.alt')}</p>
          <ul className="mt-6 space-y-2 text-sm text-muted">
            <li>{t(L, 'pricing.pro.f1')}</li>
            <li>{t(L, 'pricing.pro.f2')}</li>
            <li>{t(L, 'pricing.pro.f3')}</li>
            <li>{t(L, 'pricing.pro.f4')}</li>
          </ul>
        </div>
        <div className="rounded-2xl border border-white/12 p-8">
          <h2 className="text-xl font-semibold">{t(L, 'billing.packs.title')}</h2>
          <p className="mt-2 text-3xl font-semibold tracking-tight">
            $5<span className="text-base font-normal text-muted">{t(L, 'pricing.packs.from')}</span>
          </p>
          <p className="mt-1 text-sm text-muted">{t(L, 'pricing.packs.sub')}</p>
          <ul className="mt-6 space-y-2 text-sm text-muted">
            <li>{t(L, 'billing.packs.5')}</li>
            <li>{t(L, 'billing.packs.10')}</li>
            <li>{t(L, 'billing.packs.25')}</li>
            <li>{t(L, 'pricing.packs.f4')}</li>
          </ul>
        </div>
      </div>

      <CheckoutButtons
        plans={[
          ...SUBSCRIPTION_PLANS.map((p) => ({
            key: p.key, name: t(L, `plan.${p.key}.name`),
            priceLabel: t(L, `plan.${p.key}.price`), blurb: t(L, `plan.${p.key}.blurb`),
            available: !!p.priceId, primary: p.key === 'pro_yearly',
          })),
          ...CREDIT_PLANS.map((p) => ({
            key: p.key, name: t(L, `plan.${p.key}.name`),
            priceLabel: t(L, `plan.${p.key}.price`), blurb: t(L, `plan.${p.key}.blurb`),
            available: !!p.priceId,
          })),
        ]}
        busyLabel={t(L, 'checkout.busy')}
        errLabel={t(L, 'checkout.err')}
        loginPath={href(L, '/login')}
      />

      <p className="mt-6 text-sm text-muted">
        {t(L, 'billing.link.signedin')}
        <Link href={href(L, '/account/billing')} className="ml-1 text-accentBright underline">
          {t(L, 'billing.link.go')}
        </Link>
      </p>

      <p className="mt-10 text-xs text-muted">
        {t(L, 'billing.privacy')}
      </p>
    </main>
  );
}
