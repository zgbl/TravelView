import Link from 'next/link';
import { redirect } from 'next/navigation';
import { requireUser } from '@/lib/auth';
import { one } from '@/lib/db';
import TokenManager from '@/components/TokenManager';

export default async function Account() {
  const user = await requireUser();
  if (!user) redirect('/login');

  const row = await one<{
    story_credits: number;
    subscription_status: string | null;
    subscription_until: string | null;
  }>(`select story_credits, subscription_status, subscription_until
        from users where id = $1`, [user.id]);

  const subscribed = row?.subscription_status === 'active';

  return (
    <main className="mx-auto max-w-2xl px-6 py-16">
      <div className="mb-10 flex items-center justify-between">
        <h1 className="text-3xl font-semibold tracking-tight">账户</h1>
        <Link href="/stories" className="text-sm text-muted hover:text-paper">
          我的故事
        </Link>
      </div>

      <div className="rounded-2xl border border-white/12 p-6">
        <div className="text-sm text-muted">{user.email}</div>
        <div className="mt-4 text-sm">
          {subscribed ? (
            <span className="text-accentBright">
              订阅中，一年内不限篇数
              {row?.subscription_until &&
                `（到 ${row.subscription_until.slice(0, 10)}）`}
            </span>
          ) : (
            <span>
              可发布额度：<strong>{row?.story_credits ?? 0}</strong> 篇
            </span>
          )}
        </div>
        {!subscribed && (
          <Link
            href="/pricing"
            className="mt-5 inline-block rounded-full bg-accentBright px-5 py-2
              text-sm font-medium text-ink"
          >
            购买发布额度
          </Link>
        )}
      </div>

      <TokenManager />

      <div className="mt-12 border-t border-white/10 pt-8">
        <h2 className="text-sm font-medium">删除账户</h2>
        <p className="mt-2 text-xs text-muted">
          会删除你的全部故事和服务器上的图片。你电脑上的原图不受影响。
          需要请发邮件联系我们。
        </p>
      </div>
    </main>
  );
}

export const dynamic = 'force-dynamic';
