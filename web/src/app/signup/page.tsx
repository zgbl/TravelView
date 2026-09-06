import Link from 'next/link';
import AuthForm from '@/components/AuthForm';
import { betaState } from '@/lib/access';
import { getLocale } from '@/lib/i18n.server';
import { href, t } from '@/lib/i18n';

export const dynamic = 'force-dynamic';

export default async function Signup() {
  const beta = await betaState();
  const L = await getLocale();

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col
      justify-center px-6 py-16">
      <Link href={href(L, '/')} className="mb-10 text-sm text-muted">&larr; TravelView</Link>

      <h1 className="text-3xl font-semibold tracking-tight">{t(L, 'auth.signup.title')}</h1>
      <p className="mt-3 text-sm leading-relaxed text-muted">
        {t(L, 'auth.signup.intro')}
        <strong className="text-paper">{t(L, 'auth.signup.intro.strong')}</strong>
        {L === 'zh' ? '。' : '.'}
      </p>

      {beta.free && (
        <div className="mt-6 rounded-xl border border-accentBright/30
          bg-accentBright/5 px-4 py-3 text-sm">
          <strong className="text-accentBright">{t(L, 'beta.free.title')}</strong>
          <span className="ml-1 text-muted">{t(L, 'beta.free.signup')}</span>
        </div>
      )}

      <div className="mt-8">
        <AuthForm mode="signup" locale={L} />
      </div>

      <p className="mt-6 text-sm text-muted">
        {t(L, 'auth.have')}
        <Link href={href(L, '/login')} className="text-accentBright">
          {t(L, 'nav.login')}
        </Link>
      </p>
    </main>
  );
}
