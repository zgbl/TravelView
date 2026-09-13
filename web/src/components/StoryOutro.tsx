import Link from 'next/link';
import Logo from './Logo';
import { href, t, type Locale } from '@/lib/i18n';

/**
 * 故事读完之后的那一屏。
 *
 * **这是整个产品最大的一个入口，之前它是空的。**
 * 一篇公开的回顾会被转进群里、发到朋友圈，每一个看完的人都刚刚
 * 亲眼见过这个产品能做出什么 —— 然后页面就没了，他无处可去。
 * 那不是"克制"，那是把上门的人挡在门外。
 *
 * 两种人看到的不是同一句话：
 *   - 访客：他刚看完别人的旅行，下一个念头是"我的照片能不能也这样"
 *   - 作者本人：他多半是回来检查自己这篇的，下一步是回去接着做
 *
 * 顶上仍然不挂全站导航（那会把作品变成"某网站里的一页"），
 * 这一块放在**内容结束之后**，读者是读完了才碰到它的。
 */
export default function StoryOutro({
  locale,
  isAuthor,
}: {
  locale: Locale;
  isAuthor: boolean;
}) {
  const primary = isAuthor ? '/stories' : '/';
  const secondary = isAuthor ? '/' : '/signup';

  return (
    <section className="border-t border-white/10 bg-ink px-6 py-16">
      <div className="mx-auto flex max-w-xl flex-col items-center text-center">
        <Link
          href={href(locale, '/')}
          className="flex items-center gap-2.5 text-lg font-semibold
            tracking-tight text-paper"
        >
          <Logo size={30} />
          TravelView
        </Link>

        <h2 className="mt-6 text-2xl font-semibold leading-snug sm:text-3xl">
          {t(locale, isAuthor ? 'outro.author.title' : 'outro.title')}
        </h2>
        <p className="mt-3 text-sm leading-relaxed text-muted">
          {t(locale, isAuthor ? 'outro.author.body' : 'outro.body')}
        </p>

        <div className="mt-8 flex w-full flex-col items-stretch gap-3
          sm:w-auto sm:flex-row sm:items-center">
          <Link
            href={href(locale, primary)}
            className="rounded-full bg-accentBright px-8 py-3.5 text-center
              text-[15px] font-semibold text-ink transition hover:brightness-110"
          >
            {t(locale, isAuthor ? 'outro.author.cta' : 'outro.cta')}
          </Link>
          <Link
            href={href(locale, secondary)}
            className="rounded-full border border-white/20 px-8 py-3.5
              text-center text-[15px] text-paper transition
              hover:border-white/45"
          >
            {t(locale, isAuthor ? 'outro.author.cta2' : 'outro.cta2')}
          </Link>
        </div>

        <p className="mt-6 text-xs text-muted/80">
          {t(locale, 'outro.note')}
        </p>
      </div>
    </section>
  );
}

/**
 * 左上角那个小徽标。
 *
 * 结尾那一块只有**读到底**的人才看得到；中途划走的人同样需要一条路。
 * 做得很轻（半透明药丸、只有 logo 和站名），不抢封面。
 */
export function StoryHomeLink({ locale }: { locale: Locale }) {
  return (
    <Link
      href={href(locale, '/')}
      className="fixed left-4 top-4 z-40 flex items-center gap-2 rounded-full
        border border-white/15 bg-ink/70 px-3 py-1.5 text-[13px]
        font-medium text-paper backdrop-blur transition
        hover:border-white/40 hover:bg-ink/90"
    >
      <Logo size={18} />
      TravelView
    </Link>
  );
}
