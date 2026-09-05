import { notFound } from 'next/navigation';
import type { Metadata } from 'next';
import StoryRenderer from '@/components/StoryRenderer';
import { one, query } from '@/lib/db';
import { mediaUrl, type Story } from '@/lib/story';

type Row = {
  slug: string;
  title: string;
  subtitle: string | null;
  cover_path: string | null;
  manifest: Story;
  visibility: string;
};

async function load(slug: string) {
  return one<Row>(
    `select slug, title, subtitle, cover_path, manifest, visibility
       from stories where slug = $1 and visibility <> 'private'`,
    [slug],
  );
}

/**
 * Open Graph 必须在服务端直出 —— 各家抓取器都不执行 JavaScript。
 * 这直接决定了公开页不能做成纯客户端渲染。
 */
export async function generateMetadata(
  { params }: { params: Promise<{ slug: string }> },
): Promise<Metadata> {
  const { slug } = await params;
  const story = await load(slug);
  if (!story) return { title: 'Story not found' };

  const url = `${process.env.NEXT_PUBLIC_SITE_URL}/s/${slug}`;
  const stats = story.manifest.stats;
  const desc =
    story.subtitle ??
    `${stats.days} 天 · ${stats.stops} 站 · ${stats.photos} 张照片`;

  return {
    title: `${story.title} — TravelView`,
    description: desc,
    alternates: { canonical: url },
    openGraph: {
      type: 'article',
      url,
      title: story.title,
      description: desc,
      // 用 next/og 动态生成的 PNG。Facebook 的抓取器不吃 WebP，
      // 所以社交预览图必须是 PNG/JPEG。
      images: [{ url: `${url}/opengraph-image`, width: 1200, height: 630 }],
    },
    twitter: { card: 'summary_large_image' },
  };
}

export default async function PublicStory(
  { params }: { params: Promise<{ slug: string }> },
) {
  const { slug } = await params;
  const row = await load(slug);
  if (!row) notFound();

  // 不记录任何访客身份，只加个数
  query('select bump_story_view($1)', [slug]).catch(() => {});

  return <StoryRenderer story={row.manifest} />;
}

export const dynamic = 'force-dynamic';
