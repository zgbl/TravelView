import Link from 'next/link';
import { redirect } from 'next/navigation';
import { requireUser } from '@/lib/auth';
import { one } from '@/lib/db';
import { betaState } from '@/lib/access';
import { requireAdmin } from '@/lib/admin';
import { getLocale } from '@/lib/i18n.server';
import { href, t } from '@/lib/i18n';
import TokenManager from '@/components/TokenManager';
import NameEditor from '@/components/NameEditor';
import HandleEditor from '@/components/HandleEditor';
import PasswordEditor from '@/components/PasswordEditor';
import SignOutButton from '@/components/SignOutButton';
import { siteUrl } from '@/lib/stripe';

export default async function Account() {
  const user = await requireUser();
  if (!user) redirect('/login');

  const row = await one<{
    name: string | null;
    handle: string | null;
    story_credits: number;
    subscription_status: string | null;
    subscription_until: string | null;
  }>(`select name, handle, story_credits, subscription_status, subscription_until
        from users where id = $1`, [user.id]);

  const subscribed = row?.subscription_status === 'active';
  const beta = await betaState();
  const isAdmin = !!(await requireAdmin());
  const L = await getLocale();

  return (
    <main className="mx-auto max-w-2xl px-6 py-16">
      <div className="mb-10 flex items-center justify-between">
        <h1 className="text-3xl font-semibold tracking-tight">{t(L, 'account.title')}</h1>
        <div className="flex gap-4 text-sm">
          {isAdmin && (
            <Link href={href(L, '/admin')} className="text-muted hover:text-paper">
              {t(L, 'nav.admin')}
            </Link>
          )}
          <Link href={href(L, '/link')} className="text-muted hover:text-paper">
            {t(L, 'link.entry')}
          </Link>
          <Link href={href(L, '/stories')} className="text-muted hover:text-paper">
            {t(L, 'nav.stories')}
          </Link>
          <SignOutButton locale={L} className="text-muted hover:text-paper" />
        </div>
      </div>

      <div className="rounded-2xl border border-white/12 p-6">
        <div className="flex items-center gap-3">
          <span className="grid h-10 w-10 place-items-center rounded-full
            bg-accentBright/20 text-sm font-semibold uppercase text-accentBright">
            {(row?.name ?? user.email).trim().charAt(0)}
          </span>
          <div>
            {row?.name?.trim() && (
              <div className="text-base font-medium">{row.name}</div>
            )}
            <div className="text-sm text-muted">{user.email}</div>
          </div>
        </div>
        <div className="mt-4 text-sm">
          {beta.free ? (
            <span className="text-accentBright">
              {t(L, 'beta.free.account')}
              {(row?.story_credits ?? 0) > 0 &&
                t(L, 'account.beta.credits.kept', { n: row!.story_credits })}
            </span>
          ) : subscribed ? (
            <span className="text-accentBright">
              {t(L, 'billing.subscribed')}
              {row?.subscription_until &&
                ` (${t(L, 'billing.renews',
                  { date: row.subscription_until.slice(0, 10) })})`}
            </span>
          ) : (
            <span>
              {t(L, 'billing.credits')}
              <strong>{row?.story_credits ?? 0}</strong>
              {t(L, 'billing.credits.unit')}
            </span>
          )}
        </div>
        {/* 付费入口任何时候都在。公测期把它藏起来，等于把"现在就愿意付钱的人"
            挡在门外，而这恰恰是最值钱的早期信号。 */}
        <Link
          href={href(L, '/account/billing')}
          className={`mt-5 inline-block rounded-full px-5 py-2 text-sm font-medium
            ${subscribed
              ? 'border border-white/20 text-paper'
              : 'bg-accentBright text-ink'}`}
        >
          {subscribed ? t(L, 'billing.manage') : t(L, 'billing.entry')}
        </Link>
      </div>

      <NameEditor initial={row?.name ?? ''} locale={L} />

      <PasswordEditor locale={L} />

      <HandleEditor
        initial={row?.handle ?? ''}
        site={siteUrl().replace(/^https?:\/\//, '')}
        labels={{
          title: t(L, 'profile.handle'),
          hint: t(L, 'profile.handle.hint'),
          save: t(L, 'profile.handle.save'),
          saved: t(L, 'profile.handle.saved'),
          taken: t(L, 'profile.handle.taken'),
          bad: t(L, 'profile.handle.bad'),
          open: t(L, 'profile.handle.open'),
        }}
      />

      <TokenManager />

      <div className="mt-12 border-t border-white/10 pt-8">
        <h2 className="text-sm font-medium">{t(L, 'account.delete.title')}</h2>
        <p className="mt-2 text-xs text-muted">{t(L, 'account.delete.body')}</p>
      </div>
    </main>
  );
}

export const dynamic = 'force-dynamic';
