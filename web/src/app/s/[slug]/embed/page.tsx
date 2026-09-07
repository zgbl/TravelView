import { notFound } from 'next/navigation';
import StoryRenderer from '@/components/StoryRenderer';
import { one } from '@/lib/db';
import type { Story } from '@/lib/story';

/** 嵌进别人页面时用: 去掉结束卡片和外框，只留内容 */
export default async function Embed(
  { params }: { params: Promise<{ slug: string }> },
) {
  const { slug } = await params;
  const row = await one<{ manifest: Story; media_prefix: string | null }>(
    `select manifest, media_prefix from stories
      where slug = $1 and visibility = 'public'`,
    [slug],
  );
  if (!row) notFound();
  return (
    <StoryRenderer
      story={row.manifest}
      compact
      prefix={row.media_prefix ?? `s/${slug}`}
    />
  );
}

export const dynamic = 'force-dynamic';
