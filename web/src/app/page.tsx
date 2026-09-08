import Link from 'next/link';
import NavBar from '@/components/NavBar';
import SiteFooter from '@/components/SiteFooter';
import StoryRenderer from '@/components/StoryRenderer';
import { demoStory } from '@/lib/demo-story';
import { getLocale } from '@/lib/i18n.server';
import { href, t } from '@/lib/i18n';

/**
 * 落地页。
 *
 * 之前这里**直接就是一整篇示例游记**: 访客打开首页，看到的是一趟别人的
 * 旅行，既不知道自己在哪儿，也没有任何入口 —— 像是误点进了某个人的博客。
 * 产品演示是好东西，但它得**先被介绍，再被展示**。
 *
 * 现在的顺序是: 一句话说清这是什么 → 给它看成品（框在一个"设备"里，
 * 明确标着"示例"）→ 三步说清怎么用 → 具体能力 → 隐私的硬承诺 → 下载。
 *
 * **每一屏都能被单独截图发出去。** 这是落地页真实的使用方式。
 */
export default async function Home() {
  const L = await getLocale();

  return (
    <main className="bg-ink text-paper">
      <NavBar />

      {/* ── 首屏 ── 只有一句话、一个动作。**不放示例** ——
          先让人知道这是什么，再给他看东西 */}
      <section className="relative overflow-hidden px-6 pb-24 pt-20 md:pt-28">
        {/* 背景: 一层极淡的路线感光晕，不用图片，不拖慢首屏 */}
        <div aria-hidden className="pointer-events-none absolute inset-0
          bg-[radial-gradient(80%_60%_at_50%_0%,rgba(79,191,168,.16),transparent_70%)]" />
        <div className="relative mx-auto max-w-3xl text-center">
          <p className="text-xs uppercase tracking-[.2em] text-accentBright">
            {t(L, 'home.kicker')}
          </p>
          <h1 className="mt-5 whitespace-pre-line text-[clamp(32px,5.5vw,60px)]
            font-semibold leading-[1.1] tracking-tight">
            {t(L, 'home.h1')}
          </h1>
          <p className="mx-auto mt-6 max-w-2xl text-[15px] leading-relaxed text-muted">
            {t(L, 'home.sub')}
          </p>
          <div className="mt-9 flex flex-wrap items-center justify-center gap-3">
            <Link href={href(L, '/signup')}
              className="rounded-full bg-accentBright px-7 py-3 font-medium text-ink
                transition hover:brightness-110">
              {t(L, 'home.cta.get')}
            </Link>
            <Link href={href(L, '/download')}
              className="rounded-full border border-white/20 px-7 py-3
                transition hover:border-white/40">
              {t(L, 'home.cta.download')}
            </Link>
            <a href="#demo" className="px-3 py-3 text-sm text-muted hover:text-paper">
              {t(L, 'home.cta.try')} ↓
            </a>
          </div>
        </div>
      </section>

      {/* ── 成品 ── 框进一个"屏幕"里，并且明确标着示例。
          直接铺满整页的话，访客会以为这就是我们的网站 */}
      <section id="demo" className="border-t border-white/10 px-6 py-20">
        <div className="mx-auto max-w-6xl">
          <div className="mb-8 flex flex-wrap items-end justify-between gap-4">
            <div>
              <h2 className="text-[clamp(22px,3vw,34px)] font-semibold tracking-tight">
                {t(L, 'home.demo.title')}
              </h2>
              <p className="mt-2 max-w-xl text-sm text-muted">
                {t(L, 'home.demo.sub')}
              </p>
            </div>
            <Link href={href(L, '/demo')}
              className="rounded-full border border-white/20 px-5 py-2 text-sm
                transition hover:border-white/40">
              {t(L, 'home.demo.open')} →
            </Link>
          </div>

          {/* 假窗口: 三个圆点 + 地址栏，一眼看出"这是一个网页" */}
          <div className="overflow-hidden rounded-2xl border border-white/12
            bg-black/40 shadow-2xl">
            <div className="flex items-center gap-2 border-b border-white/10
              bg-white/[.04] px-4 py-2.5">
              <span className="h-2.5 w-2.5 rounded-full bg-white/25" />
              <span className="h-2.5 w-2.5 rounded-full bg-white/25" />
              <span className="h-2.5 w-2.5 rounded-full bg-white/25" />
              <span className="ml-3 truncate text-[11px] text-muted">
                travelview.app/s/demo
              </span>
            </div>
            {/* 固定高度 + 内部滚动: 示例不该把整个落地页撑成十屏 */}
            <div className="h-[70vh] overflow-y-auto">
              <StoryRenderer story={demoStory} compact locale={L} />
            </div>
          </div>
        </div>
      </section>

      {/* ── 三步 ── */}
      <section className="border-t border-white/10 px-6 py-20">
        <div className="mx-auto max-w-6xl">
          <h2 className="text-[clamp(22px,3vw,34px)] font-semibold tracking-tight">
            {t(L, 'home.how')}
          </h2>
          <p className="mt-2 text-sm text-muted">{t(L, 'home.how.sub')}</p>
          <ol className="mt-10 grid gap-8 md:grid-cols-3">
            {[1, 2, 3].map((n) => (
              <li key={n} className="rounded-2xl border border-white/10
                bg-white/[.03] p-6">
                <span className="flex h-8 w-8 items-center justify-center
                  rounded-full bg-accentBright text-sm font-semibold text-ink">
                  {n}
                </span>
                <h3 className="mt-4 text-lg font-semibold">
                  {t(L, `home.how.${n}.t`)}
                </h3>
                <Body text={t(L, `home.how.${n}.b`)} />
              </li>
            ))}
          </ol>
        </div>
      </section>

      {/* ── 能力 ── */}
      <section className="border-t border-white/10 px-6 py-20">
        <div className="mx-auto grid max-w-6xl gap-x-12 gap-y-10 md:grid-cols-3">
          {['route', 'pick', 'player', 'local', 'two', 'own'].map((k) => (
            <div key={k}>
              <h3 className="text-base font-semibold">{t(L, `home.f.${k}`)}</h3>
              <Body text={t(L, `home.f.${k}.b`)} />
            </div>
          ))}
        </div>
      </section>

      {/* ── 隐私 ── 单独一屏。**这是最强的差异点**，
          和别的功能并排列成一个小格子是浪费 */}
      <section className="border-t border-white/10 px-6 py-20">
        <div className="mx-auto max-w-3xl">
          <h2 className="text-[clamp(22px,3vw,34px)] font-semibold tracking-tight">
            {t(L, 'home.privacy.t')}
          </h2>
          <p className="mt-5 text-[15px] leading-relaxed text-muted">
            {t(L, 'home.privacy.b')}
          </p>
        </div>
      </section>

      {/* ── 收尾 ── */}
      <section className="border-t border-white/10 px-6 py-24 text-center">
        <h2 className="text-[clamp(24px,4vw,42px)] font-semibold tracking-tight">
          {t(L, 'home.final.t')}
        </h2>
        <p className="mx-auto mt-4 max-w-xl text-muted">{t(L, 'home.final.b')}</p>
        <div className="mt-9 flex flex-wrap items-center justify-center gap-3">
          <Link href={href(L, '/signup')}
            className="rounded-full bg-accentBright px-7 py-3 font-medium text-ink">
            {t(L, 'home.cta.get')}
          </Link>
          <Link href={href(L, '/pricing')}
            className="rounded-full border border-white/20 px-7 py-3">
            {t(L, 'nav.pricing')}
          </Link>
        </div>
      </section>

      <SiteFooter />
    </main>
  );
}

/// 正文里用 **加粗** 标出一句话里最要紧的半句 —— 落地页是扫读的
function Body({ text }: { text: string }) {
  const parts = text.split(/\*\*(.+?)\*\*/g);
  return (
    <p className="mt-2 text-sm leading-relaxed text-muted">
      {parts.map((s, i) =>
        i % 2 ? <strong key={i} className="text-paper">{s}</strong> : s)}
    </p>
  );
}
