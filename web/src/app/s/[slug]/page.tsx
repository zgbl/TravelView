import { notFound } from 'next/navigation';
import type { Metadata } from 'next';
import StoryRenderer from '@/components/StoryRenderer';
import ShareBar from '@/components/ShareBar';
import { getLocale } from '@/lib/i18n.server';
import { one, query } from '@/lib/db';
import { mediaUrl, type Story } from '@/lib/story';

type Row = {
  slug: string;
  media_prefix: string | null;
  title: string;
  subtitle: string | null;
  cover_path: string | null;
  manifest: Story;
  visibility: string;
};

async function load(slug: string) {
  return one<Row>(
    `select slug, media_prefix, title, subtitle, cover_path, manifest, visibility
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

  /**
   * 预览图给两张，顺序有讲究:
   *
   * 1. `og.jpg` —— 导出时生成的静态 JPEG。**微信只吃这种**:
   *    它的抓取器不解 WebP，也不会去等一个动态渲染的接口，
   *    超时就直接不显示图（就是那张光秃秃的方块卡）。
   * 2. `opengraph-image` —— next/og 动态合成的那张（封面 + 标题 + 数字），
   *    Facebook / Twitter 会用第一张，但老故事没有 og.jpg 时它兜底。
   */
  const prefix = story.media_prefix ?? `s/${story.slug}`;
  const ogPath = (story.manifest as { ogImage?: string }).ogImage;
  const images = [
    ...(ogPath
      ? [{ url: mediaUrl(ogPath, prefix), width: 1200, height: 900 }]
      : []),
    { url: `${url}/opengraph-image`, width: 1200, height: 630 },
  ];

  return {
    // 浏览器标签页带上站名，社交卡片**不带** ——
    // 微信那张卡只有一行标题的宽度，"— TravelView" 会把真正的内容挤没
    title: `${story.title} — TravelView`,
    description: desc,
    alternates: { canonical: url },
    openGraph: {
      type: 'article',
      url,
      siteName: 'TravelView',
      title: story.title,
      description: desc,
      images,
    },
    twitter: { card: 'summary_large_image', title: story.title, description: desc },
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

  const locale = await getLocale();
  const url = `${process.env.NEXT_PUBLIC_SITE_URL}/${locale}/s/${row.slug}`;
  return (
    <>
      {/* 底部分享条是固定的，留出空间，别压住结束卡片 */}
      <div className="pb-24">
        <StoryRenderer
          locale={locale}
          story={row.manifest}
          prefix={row.media_prefix ?? `s/${row.slug}`}
        />
      </div>
      {/* 未公开的（unlisted）也给分享入口 —— 用户自己拿链接给谁是他的事 */}
      <ShareBar url={url} title={row.title} locale={locale} />
    </>
  );
}

export const dynamic = 'force-dynamic';
