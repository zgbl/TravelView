import Link from 'next/link';
import AuthForm from '@/components/AuthForm';
import { getLocale } from '@/lib/i18n.server';
import { href, t } from '@/lib/i18n';

export default async function Login() {
  const L = await getLocale();
  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col
      justify-center px-6 py-16">
      <Link href={href(L, '/')} className="mb-10 text-sm text-muted">&larr; TravelView</Link>

      <h1 className="text-3xl font-semibold tracking-tight">{t(L, 'auth.login.title')}</h1>
      <p className="mt-3 text-sm text-muted">
        {t(L, 'auth.login.intro')}
      </p>

      <div className="mt-8">
        <AuthForm mode="login" locale={L} />
      </div>

      <p className="mt-6 text-sm text-muted">
        {t(L, 'auth.havent')}
        <Link href={href(L, '/signup')} className="text-accentBright">
          {t(L, 'auth.submit.signup')}
        </Link>
      </p>
    </main>
  );
}
