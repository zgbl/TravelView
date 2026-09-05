import Link from 'next/link';
import { redirect } from 'next/navigation';
import { requireUser } from '@/lib/auth';
import { query } from '@/lib/db';
import { miles } from '@/lib/story';

type Row = {
  id: string; slug: string; title: string; subtitle: string | null;
  day_count: number; stop_count: number; photo_count: number;
  distance_meters: string; visibility: string; view_count: string;
  published_at: string | null;
};

export default async function MyStories() {
  const user = await requireUser();
  if (!user) redirect('/login');

  const rows = await query<Row>(
    `select id, slug, title, subtitle, day_count, stop_count, photo_count,
            distance_meters, visibility, view_count, published_at
       from stories where user_id = $1 order by created_at desc`,
    [user.id],
  );

  return (
    <main className="mx-auto max-w-4xl px-6 py-16">
      <div className="mb-10 flex items-center justify-between">
        <h1 className="text-3xl font-semibold tracking-tight">我的旅行故事</h1>
        <Link href="/account" className="text-sm text-muted hover:text-paper">
          账户
        </Link>
      </div>

      {rows.length === 0 ? (
        <div className="rounded-2xl border border-white/12 p-10 text-center">
          <p className="text-muted">
            还没有发布过。在桌面端挑好照片后点「发布」，故事会出现在这里。
          </p>
          <Link
            href="/account"
            className="mt-6 inline-block rounded-full bg-accentBright px-6 py-2.5
              text-sm font-medium text-ink"
          >
            获取发布令牌
          </Link>
        </div>
      ) : (
        <ul className="space-y-3">
          {rows.map((s) => (
            <li key={s.id}>
              <Link
                href={`/stories/${s.id}`}
                className="flex items-center justify-between rounded-2xl
                  border border-white/12 px-6 py-5 hover:border-white/25"
              >
                <div>
                  <div className="font-medium">{s.title}</div>
                  <div className="mt-1 text-xs text-muted">
                    {s.day_count} 天 · {s.stop_count} 站 ·{' '}
                    {miles(Number(s.distance_meters))} mi · {s.photo_count} 张
                    {s.visibility !== 'public' && ` · ${s.visibility}`}
                  </div>
                </div>
                <div className="text-right text-xs text-muted">
                  <div>{Number(s.view_count)} 次浏览</div>
                  <div className="mt-1">/s/{s.slug}</div>
                </div>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}

export const dynamic = 'force-dynamic';
