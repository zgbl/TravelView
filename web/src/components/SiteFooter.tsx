import Link from 'next/link';
import { getLocale } from '@/lib/i18n.server';
import { href, t } from '@/lib/i18n';
import { featuredStory, featuredHref } from '@/lib/featured';
import LangSwitch from './LangSwitch';
import Logo from './Logo';

/**
 * 全站页脚。
 *
 * 页脚是**网站地图的最后一份备份**: 用户在任何一页走到底，
 * 都该能找到去别处的路，而不是只剩一行版权。
 */
export default async function SiteFooter() {
  const L = await getLocale();
  const featured = await featuredStory();
  const item = 'text-sm text-muted transition-colors hover:text-paper';
  return (
    <footer className="border-t border-white/10 px-6 py-12">
      <div className="mx-auto flex max-w-6xl flex-wrap items-start gap-x-12 gap-y-8">
        <div className="mr-auto">
          <Link href={href(L, '/')}
            className="flex items-center gap-2.5 font-semibold tracking-tight">
            <Logo size={22} />
            TravelView
          </Link>
          <p className="mt-3 max-w-xs text-xs leading-relaxed text-muted">
            {t(L, 'home.kicker')}
          </p>
        </div>

        <nav className="flex flex-col gap-2.5">
          <Link href={href(L, '/download')} className={item}>{t(L, 'nav.download')}</Link>
          <Link href={href(L, '/pricing')} className={item}>{t(L, 'nav.pricing')}</Link>
          <Link href={href(L, featuredHref(featured))} className={item}>
            {t(L, 'home.demo.open')}
          </Link>
        </nav>
        <nav className="flex flex-col gap-2.5">
          <Link href={href(L, '/login')} className={item}>{t(L, 'nav.login')}</Link>
          <Link href={href(L, '/signup')} className={item}>{t(L, 'nav.start')}</Link>
          <LangSwitch locale={L} />
        </nav>
      </div>

      <div className="mx-auto mt-10 max-w-6xl border-t border-white/10 pt-6
        text-xs text-muted">
        TravelView &middot; 地图数据 &copy; OpenStreetMap 贡献者
      </div>
    </footer>
  );
}
