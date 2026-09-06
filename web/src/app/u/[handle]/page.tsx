import Link from 'next/link';
import { notFound } from 'next/navigation';
import type { Metadata } from 'next';
import { one, query } from '@/lib/db';
import { requireUser } from '@/lib/auth';
import { mediaUrl, miles, type Story } from '@/lib/story';
import { getLocale } from '@/lib/i18n.server';
import { href, t } from '@/lib/i18n';
import { siteUrl } from '@/lib/stripe';
import ShareBar from '@/components/ShareBar';

export const dynamic = 'force-dynamic';

type Owner = {
  id: string; handle: string; name: string | null;
  bio: string | null; profile_public: boolean;
};

type Card = {
  id: string; slug: string; title: string; subtitle: string | null;
  media_prefix: string | null; manifest: Story;
  day_count: number; stop_count: number; photo_count: number;
  distance_meters: string; published_at: string | null;
};

async function load(handle: string) {
  const owner = await one<Owner>(
    `select id, handle, name, bio, profile_public
       from users where lower(handle) = lower($1) and banned_at is null`,
    [handle]);
  if (!owner) return null;
  // 主页只列公开的。unlisted 的故事拿到链接才能看，不该出现在任何列表里 ——
  // 这是"仅凭链接访问"这个承诺的一部分
  const stories = await query<Card>(
    `select id, slug, title, subtitle, media_prefix, manifest, day_count,
            stop_count, photo_count, distance_meters, published_at
       from stories
      where user_id = $1 and visibility = 'public'
      order by coalesce(published_at, created_at) desc`,
    [owner.id]);
  return { owner, stories };
}

export async function generateMetadata(
  { params }: { params: Promise<{ handle: string }> },
): Promise<Metadata> {
  const { handle } = await params;
  const data = await load(handle);
  if (!data) return { title: 'Not found' };
  const name = data.owner.name ?? data.owner.handle;
  return {
    title: `${name} — TravelView`,
    description: data.owner.bio ?? undefined,
    alternates: { canonical: `${siteUrl()}/u/${data.owner.handle}` },
    openGraph: { type: 'profile', title: name },
  };
}

export default async function Profile(
  { params }: { params: Promise<{ handle: string }> },
) {
  const { handle } = await params;
  const data = await load(handle);
  if (!data) notFound();

  const { owner, stories } = data;
  const me = await requireUser();
  const isOwner = me?.id === owner.id;
  // 关掉主页的人自己还能看到，别人一律 404 —— 显示"这个人隐藏了主页"
  // 等于泄露了这个 handle 有人在用
  if (!owner.profile_public && !isOwner) notFound();

  const L = await getLocale();
  const url = `${siteUrl()}/u/${owner.handle}`;

  return (
    <main className="mx-auto max-w-5xl px-6 py-16">
      <header className="border-b border-white/10 pb-10">
        <h1 className="text-4xl font-semibold tracking-tight">
          {owner.name ?? owner.handle}
        </h1>
        <p className="mt-2 text-sm text-muted">@{owner.handle}</p>
        {owner.bio && (
          <p className="mt-4 max-w-xl text-muted">{owner.bio}</p>
        )}
        <p className="mt-4 text-xs text-muted">
          {t(L, 'profile.stories', { n: stories.length })}
        </p>
        <div className="mt-6">
          <ShareBar url={url} title={owner.name ?? owner.handle} locale={L} />
        </div>
        {isOwner && (
          <p className="mt-6 rounded-xl border border-accentBright/30
            bg-accentBright/5 px-4 py-3 text-sm text-muted">
            {t(L, 'profile.own.cta')}
          </p>
        )}
      </header>

      {stories.length === 0 ? (
        <p className="mt-16 text-center text-muted">{t(L, 'profile.empty')}</p>
      ) : (
        <ul className="mt-10 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {stories.map((s) => {
            const prefix = s.media_prefix ?? `s/${s.slug}`;
            const cover = s.manifest.cover
              ? s.manifest.photos.find((p) => p.id === s.manifest.cover)
              : s.manifest.photos[0];
            return (
              <li key={s.id}>
                <Link
                  href={href(L, `/s/${s.slug}`)}
                  className="group block overflow-hidden rounded-2xl
                    border border-white/12 hover:border-white/25"
                >
                  <div className="aspect-[4/3] overflow-hidden bg-white/5">
                    {cover && (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={mediaUrl(cover.web.path, prefix)}
                        alt=""
                        loading="lazy"
                        className="h-full w-full object-cover transition
                          duration-500 group-hover:scale-[1.03]"
                      />
                    )}
                  </div>
                  <div className="p-5">
                    <div className="font-medium">{s.title}</div>
                    <div className="mt-1 text-xs text-muted">
                      {s.day_count} · {s.stop_count} · {s.photo_count} ·{' '}
                      {miles(Number(s.distance_meters))} mi
                    </div>
                  </div>
                </Link>
              </li>
            );
          })}
        </ul>
      )}

      <p className="mt-16 text-center text-xs text-muted">
        <Link href={href(L, '/')} className="hover:text-paper">
          {t(L, 'profile.made')}
        </Link>
      </p>
    </main>
  );
}
