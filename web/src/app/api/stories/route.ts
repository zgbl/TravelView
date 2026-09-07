import { NextResponse } from 'next/server';
import { one, query } from '@/lib/db';

export const dynamic = 'force-dynamic';

/**
 * 桌面端用发布令牌列出**自己已发布的故事**。
 *
 * 为什么需要: 草稿里那条"上次发布的是哪一篇"的记录会断
 * —— 换了台电脑、重建了草稿、或者内容改得指纹对不上。
 * 断了之后用户就没有任何办法更新自己的东西，只能重发一篇，
 * 旧链接还留在外面。给他一张列表自己挑，这条路就永远不会堵死。
 */
export async function GET(req: Request) {
  const token = (req.headers.get('authorization') ?? '')
    .replace(/^Bearer\s+/i, '').trim();
  if (!token) return NextResponse.json({ error: '缺少发布令牌' }, { status: 401 });

  const owner = await one<{ user_id: string }>(
    `select user_id from publish_tokens
      where token = $1 and revoked_at is null`, [token]);
  if (!owner) return NextResponse.json({ error: '令牌无效' }, { status: 401 });

  const rows = await query<{
    id: string; slug: string; title: string; start_date: string | null;
    end_date: string | null; photo_count: number; stop_count: number;
    published_at: string | null;
  }>(`select id, slug, title, start_date, end_date, photo_count, stop_count,
             published_at
        from stories where user_id = $1
       order by coalesce(published_at, created_at) desc limit 50`,
    [owner.user_id]);

  const site = (process.env.NEXT_PUBLIC_SITE_URL ?? '').replace(/\/+$/, '');
  return NextResponse.json({
    stories: rows.map((r) => ({
      id: r.id,
      slug: r.slug,
      title: r.title,
      start: r.start_date,
      end: r.end_date,
      photos: r.photo_count,
      stops: r.stop_count,
      published: !!r.published_at,
      url: `${site}/s/${r.slug}`,
    })),
  });
}
