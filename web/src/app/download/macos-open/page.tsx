import NavBar from '@/components/NavBar';
import SiteFooter from '@/components/SiteFooter';
import { getLocale } from '@/lib/i18n.server';
import { href } from '@/lib/i18n';

export const dynamic = 'force-dynamic';

// 每张帮助图（web/public/docs/macos-open/ 下的静态文件）
const IMG = {
  warning: '/docs/macos-open/step-1-warning.png',
  settings: '/docs/macos-open/step-2-settings.png',
  password: '/docs/macos-open/step-3-password.png',
  open: '/docs/macos-open/step-4-open.png',
};

const text: Record<string, { zh: string; en: string }> = {
  title: { zh: 'macOS 打不开 TravelView？', en: 'Can’t open TravelView on macOS?' },
  lead: {
    zh: '第一次打开时，macOS 会拦下没经过 App Store 签名/公证的应用，提示“无法验证开发者”。\n这是系统的安全机制，不是病毒。按下面几步放行一次即可，之后正常打开。',
    en: 'The first time you open it, macOS may block an app that isn’t signed or notarized, saying it “cannot be verified”.\nThat is the system’s security feature, not a virus. Allow it once below and it will open normally afterwards.',
  },
  step1title: { zh: '① 看到这个警告', en: '1. The warning' },
  step1body: {
    zh: '双击 .dmg 里的 TravelView 后，可能弹出“无法打开，因为无法验证开发者”。点“好/取消”先关掉。',
    en: 'After opening TravelView from the .dmg, macOS may say it “cannot be opened because the developer cannot be verified”. Click Cancel to dismiss it.',
  },
  step2title: { zh: '② 在“隐私与安全性”里允许', en: '2. Allow it in Privacy & Security' },
  step2body: {
    zh: '打开 系统设置 → 隐私与安全性，向下滚到“安全性”。会看到 TravelView 被拦截，点旁边的“仍要打开”(Open Anyway)。',
    en: 'Open System Settings → Privacy & Security and scroll to the Security section. You’ll see TravelView was blocked — click “Open Anyway” beside it.',
  },
  step3title: { zh: '③ 输入密码确认', en: '3. Confirm with your password' },
  step3body: {
    zh: '系统要求管理员权限，输入你的 Mac 登录密码并确认。',
    en: 'macOS asks for administrator rights. Enter your Mac login password and confirm.',
  },
  step4title: { zh: '④ 正常打开', en: '4. It opens' },
  step4body: {
    zh: '再次打开 TravelView（或回下载目录重新双击），这次就能正常启动了，以后无需再操作。',
    en: 'Open TravelView again — it now launches normally. You won’t need to do this again.',
  },
  alt: {
    zh: '另一种方法：右键（按住 Control 点）应用 → 选“打开”→ 再点一次“打开”，也能进入同一个允许流程。',
    en: 'Alternative: Control-click (right-click) the app → choose Open → click Open again. This triggers the same allow flow.',
  },
  back: { zh: '← 返回下载页', en: '← Back to downloads' },
};

export default async function MacOpenPage() {
  const L = await getLocale();
  const T = (k: string) => text[k]?.[L] ?? text[k]?.['en'] ?? k;

  const steps = [
    { key: '1', title: 'step1title', body: 'step1body', img: IMG.warning, alt: 'macOS warning' },
    { key: '2', title: 'step2title', body: 'step2body', img: IMG.settings, alt: 'Privacy & Security settings' },
    { key: '3', title: 'step3title', body: 'step3body', img: IMG.password, alt: 'password prompt' },
    { key: '4', title: 'step4title', body: 'step4body', img: IMG.open, alt: 'app opens' },
  ];

  return (
    <main className="min-h-screen bg-ink text-paper">
      <NavBar />
      <section className="mx-auto max-w-4xl px-6 py-16">
        <a href={href(L, '/download')} className="inline-block text-sm text-muted hover:text-paper">
          {T('back')}
        </a>
        <h1 className="mt-4 text-[clamp(26px,4vw,40px)] font-semibold tracking-tight">{T('title')}</h1>
        <p className="mt-4 max-w-3xl whitespace-pre-line text-sm leading-relaxed text-muted">{T('lead')}</p>

        <ol className="mt-10 space-y-10">
          {steps.map((s) => (
            <li key={s.key} className="flex flex-col gap-3 sm:flex-row sm:items-start">
              <div className="flex-1">
                <h2 className="text-base font-semibold text-paper">{T(s.title)}</h2>
                <p className="mt-2 max-w-xl text-sm leading-relaxed text-muted">{T(s.body)}</p>
              </div>
              <div className="w-full shrink-0 sm:w-60">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={s.img} alt={s.alt} loading="lazy"
                  className="w-full rounded-lg border border-white/10 bg-white/[.03]" />
              </div>
            </li>
          ))}
        </ol>

        <p className="mt-8 rounded-xl border border-white/10 bg-white/[.03] px-5 py-4 text-sm text-muted">
          {T('alt')}
        </p>
      </section>
      <SiteFooter />
    </main>
  );
}
