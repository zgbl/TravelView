import Link from 'next/link';
import CheckoutButtons from '@/components/CheckoutButtons';
import { betaState } from '@/lib/access';
import { getLocale, href, t } from '@/lib/i18n';

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
        <div className="rounded-2xl border border-white/12 p-8">
          <h2 className="text-xl font-semibold">发布一篇</h2>
          <p className="mt-2 text-sm text-muted">
            一次付费，一个永久有效的公开链接。
          </p>
          <ul className="mt-6 space-y-2 text-sm text-muted">
            <li>永久公开地址，可随时更新内容</li>
            <li>社交平台分享预览图</li>
            <li>随时可以删除</li>
          </ul>
        </div>
        <div className="rounded-2xl border border-accentBright/40 bg-accentBright/5 p-8">
          <h2 className="text-xl font-semibold">一年不限篇数</h2>
          <p className="mt-2 text-sm text-muted">
            经常旅行的话更划算。
          </p>
          <ul className="mt-6 space-y-2 text-sm text-muted">
            <li>一年内发布任意多篇</li>
            <li>同样永久有效</li>
          </ul>
        </div>
      </div>

      <CheckoutButtons />

      <p className="mt-10 text-xs text-muted">
        无论哪一档，原图都不会上传。服务器上只有你挑中的那些照片的压缩版本。
      </p>
    </main>
  );
}
