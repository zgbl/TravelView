import Link from 'next/link';
import ResetForm from '@/components/ResetForm';
import { getLocale } from '@/lib/i18n.server';
import { href, t } from '@/lib/i18n';

/**
 * 邮件里那个链接落在这里。token 在查询串上。
 *
 * **token 不在这里校验。** 这一页只负责收新密码，真假由提交时的接口说了算 ——
 * 先查一次再显示表单，等于给猜 token 的人一个免费的判定器。
 */
export default async function Reset(
  { searchParams }: { searchParams: Promise<{ token?: string }> },
) {
  const L = await getLocale();
  const { token } = await searchParams;

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col
      justify-center px-6 py-16">
      <Link href={href(L, '/login')} className="mb-10 text-sm text-muted">
        &larr; {t(L, 'auth.submit.login')}
      </Link>

      <h1 className="text-3xl font-semibold tracking-tight">
        {t(L, 'reset.title')}
      </h1>

      {token ? (
        <>
          <p className="mt-3 text-sm leading-relaxed text-muted">
            {t(L, 'reset.intro')}
          </p>
          <div className="mt-8">
            <ResetForm token={token} locale={L} />
          </div>
        </>
      ) : (
        <>
          <p className="mt-3 text-sm leading-relaxed text-muted">
            {t(L, 'reset.notoken')}
          </p>
          <Link href={href(L, '/forgot')}
            className="mt-6 inline-block rounded-xl bg-accentBright px-6 py-3
              text-sm font-medium text-ink">
            {t(L, 'forgot.submit')}
          </Link>
        </>
      )}
    </main>
  );
}
