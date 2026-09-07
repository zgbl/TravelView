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
  start_date: string | null; end_date: string | null;
};

export default async function MyStories() {
  const user = await requireUser();
  if (!user) redirect('/login');

  const rows = await query<Row>(
    `select id, slug, title, subtitle, day_count, stop_count, photo_count,
            distance_meters, visibility, view_count, published_at,
            start_date, end_date
       from stories where user_id = $1 order by created_at desc`,
    [user.id],
  );

  /**
   * 日期重叠 = 很可能是**同一趟行程发了两次**。
   *
   * 用户自己几乎发现不了: 两篇标题一样、统计数字只差一点，
   * 混在列表里看着就是两条普通记录。标出来，他才有机会删掉多的那篇 ——
   * 而删掉重复的那篇会把当时扣的额度退回去。
   */
  const dupIds = new Set<string>();
  for (const a of rows) {
    if (!a.start_date || !a.end_date) continue;
    for (const b of rows) {
      if (a.id === b.id || !b.start_date || !b.end_date) continue;
      if (a.start_date <= b.end_date && a.end_date >= b.start_date) {
        dupIds.add(a.id);
        break;
      }
    }
  }

  return (
    <main className="mx-auto max-w-4xl px-6 py-16">
      <div className="mb-10 flex items-center justify-between">
        <h1 className="text-3xl font-semibold tracking-tight">我的旅行故事</h1>
        <Link href="/account" className="text-sm text-muted hover:text-paper">
          账户
        </Link>
      </div>

      {dupIds.size > 1 && (
        <p className="mb-6 rounded-xl border border-amber-400/30
          bg-amber-400/5 px-5 py-4 text-sm text-muted">
          <strong className="text-amber-400">发现日期重叠的故事</strong>
          ，可能是同一趟行程发布了两次。删掉多余的那篇，
          当时扣的额度会退回你的账户（只要还留着至少一篇）。
        </p>
      )}

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
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{s.title}</span>
                    {dupIds.has(s.id) && (
                      <span className="rounded-full bg-amber-400/15 px-2 py-0.5
                        text-[10px] text-amber-400">
                        可能重复
                      </span>
                    )}
                    {!s.published_at && (
                      <span className="rounded-full bg-white/10 px-2 py-0.5
                        text-[10px] text-muted">
                        没传完
                      </span>
                    )}
                  </div>
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
