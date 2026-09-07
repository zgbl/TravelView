import Link from 'next/link';
import { notFound, redirect } from 'next/navigation';
import { requireUser } from '@/lib/auth';
import { one } from '@/lib/db';
import StoryActions from '@/components/StoryActions';
import { miles, type Story } from '@/lib/story';

export default async function ManageStory(
  { params }: { params: Promise<{ id: string }> },
) {
  const user = await requireUser();
  if (!user) redirect('/login');
  const { id } = await params;

  const row = await one<{
    id: string; slug: string; title: string; visibility: string;
    view_count: string; manifest: Story;
  }>(
    `select id, slug, title, visibility, view_count, manifest
       from stories where id = $1 and user_id = $2`,
    [id, user.id],
  );
  if (!row) notFound();

  const url = `${process.env.NEXT_PUBLIC_SITE_URL}/s/${row.slug}`;
  const st = row.manifest.stats;

  return (
    <main className="mx-auto max-w-3xl px-6 py-16">
      <Link href="/stories" className="text-sm text-muted">&larr; 我的故事</Link>
      <h1 className="mt-6 text-3xl font-semibold tracking-tight">{row.title}</h1>
      <p className="mt-2 text-sm text-muted">
        {st.days} 天 · {st.stops} 站 · {miles(st.distanceMeters)} mi ·{' '}
        {st.photos} 张 · {Number(row.view_count)} 次浏览
      </p>

      <div className="mt-8 rounded-2xl border border-white/12 p-6">
        <div className="text-xs text-muted">公开地址</div>
        <a href={url} className="mt-1 block break-all text-accentBright">
          {url}
        </a>
      </div>

      <StoryActions
        id={row.id}
        slug={row.slug}
        visibility={row.visibility}
        title={row.title}
        views={Number(row.view_count)}
        stats={`${st.days} 天 · ${st.stops} 站 · ${
          miles(st.distanceMeters)} mi · ${st.photos} 张`}
      />
    </main>
  );
}

export const dynamic = 'force-dynamic';
