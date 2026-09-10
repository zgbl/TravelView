import Link from 'next/link';
import { requireUser } from '@/lib/auth';
import { getLocale } from '@/lib/i18n.server';
import { href, t } from '@/lib/i18n';
import Logo from './Logo';
import SignOutButton from './SignOutButton';

/**
 * 全站导航。
 *
 * 之前只有落地页顶部有几个链接，其余页面（价格、账户、故事、主页）
 * 之间根本没有路走 —— 读者进了一篇故事就出不来。
 * **回首页的那个 logo 是最基本的一条路**，任何网站都得有。
 *
 * 公开的 Story 页故意不挂它: 那是一件作品，顶上压一条产品导航
 * 会把作品变成"某个网站里的一页"。那一页的回链在页脚。
 */
export default async function NavBar() {
  const L = await getLocale();
  const user = await requireUser();

  const item = 'text-sm text-muted transition-colors hover:text-paper';

  return (
    <header className="sticky top-0 z-30 border-b border-white/10
      bg-ink/85 backdrop-blur">
      <nav className="mx-auto flex max-w-6xl items-center gap-6 px-6 py-3">
        <Link href={href(L, '/')}
          className="flex items-center gap-2.5 font-semibold tracking-tight">
          <Logo size={26} />
          TravelView
        </Link>

        <div className="ml-auto flex items-center gap-5">
          <Link href={href(L, '/download')} className={item}>
            {t(L, 'nav.download')}
          </Link>
          <Link href={href(L, '/pricing')} className={item}>
            {t(L, 'nav.pricing')}
          </Link>
          {user ? (
            <>
              <Link href={href(L, '/stories')} className={item}>
                {t(L, 'nav.stories')}
              </Link>
              {/*
                **登录之后就要看得见自己是谁。**
                之前这里写死一个"账户"，同一台电脑上有两个账号的人
                （很常见：自己的 + 测试的）根本分不清现在是哪个身份在发布。
                显示名没设就退回邮箱 —— 总有一个能认出人来。
              */}
              <Link href={href(L, '/account')}
                className="flex items-center gap-2 rounded-full border
                  border-white/15 px-3 py-1.5 text-sm hover:border-white/35">
                <span className="grid h-6 w-6 place-items-center rounded-full
                  bg-accentBright/20 text-[11px] font-semibold uppercase
                  text-accentBright">
                  {(user.name ?? user.email).trim().charAt(0)}
                </span>
                <span className="max-w-[11rem] truncate">
                  {user.name?.trim() || user.email}
                </span>
              </Link>
              <SignOutButton locale={L} className={item} />
            </>
          ) : (
            <>
              <Link href={href(L, '/login')} className={item}>
                {t(L, 'nav.login')}
              </Link>
              <Link href={href(L, '/signup')}
                className="rounded-full bg-accentBright px-4 py-1.5
                  text-sm font-medium text-ink">
                {t(L, 'nav.start')}
              </Link>
            </>
          )}
        </div>
      </nav>
    </header>
  );
}
