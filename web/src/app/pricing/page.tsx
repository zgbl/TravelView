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
          <h2 className="text-xl font-semibold">Pro · 不限篇数</h2>
          <p className="mt-2 text-3xl font-semibold tracking-tight">
            $50<span className="text-base font-normal text-muted"> / 年</span>
          </p>
          <p className="mt-1 text-sm text-muted">或 $8 / 月，随时取消</p>
          <ul className="mt-6 space-y-2 text-sm text-muted">
            <li>一年内发布任意多篇</li>
            <li>永久有效的公开地址，随时可更新</li>
            <li>社交平台分享预览图</li>
            <li>退订后已发布的内容不受影响</li>
          </ul>
        </div>
        <div className="rounded-2xl border border-white/12 p-8">
          <h2 className="text-xl font-semibold">额度包 · 按篇买</h2>
          <p className="mt-2 text-3xl font-semibold tracking-tight">
            $5<span className="text-base font-normal text-muted"> 起</span>
          </p>
          <p className="mt-1 text-sm text-muted">不想订阅就买额度，买了不过期</p>
          <ul className="mt-6 space-y-2 text-sm text-muted">
            <li>$5 = 2 篇（$2.5 一篇）</li>
            <li>$10 = 5 篇（$2 一篇）</li>
            <li>$25 = 15 篇（$1.67 一篇）</li>
            <li>额度不过期，和订阅可以并存</li>
          </ul>
        </div>
      </div>

      <CheckoutButtons
        plans={[
          ...SUBSCRIPTION_PLANS.map((p) => ({
            key: p.key, name: p.name, priceLabel: p.priceLabel,
            blurb: p.blurb, available: !!p.priceId,
            primary: p.key === 'pro_yearly',
          })),
          ...CREDIT_PLANS.map((p) => ({
            key: p.key, name: p.name, priceLabel: p.priceLabel,
            blurb: p.blurb, available: !!p.priceId,
          })),
        ]}
      />

      <p className="mt-6 text-sm text-muted">
        已经注册了？
        <Link href={href(L, '/account/billing')} className="ml-1 text-accentBright underline">
          去「订阅与额度」查看当前权益并付款
        </Link>
      </p>

      <p className="mt-10 text-xs text-muted">
        无论哪一档，原图都不会上传。服务器上只有你挑中的那些照片的压缩版本。
      </p>
    </main>
  );
}
