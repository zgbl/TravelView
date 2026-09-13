import Link from 'next/link';
import ForgotForm from '@/components/ForgotForm';
import { getLocale } from '@/lib/i18n.server';
import { href, t } from '@/lib/i18n';

export default async function Forgot() {
  const L = await getLocale();
  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col
      justify-center px-6 py-16">
      <Link href={href(L, '/login')} className="mb-10 text-sm text-muted">
        &larr; {t(L, 'auth.submit.login')}
      </Link>

      <h1 className="text-3xl font-semibold tracking-tight">
        {t(L, 'forgot.title')}
      </h1>
      <p className="mt-3 text-sm leading-relaxed text-muted">
        {t(L, 'forgot.intro')}
      </p>

      <div className="mt-8">
        <ForgotForm locale={L} />
      </div>
    </main>
  );
}
