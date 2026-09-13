import { NextResponse } from 'next/server';
import { one } from '@/lib/db';
import type { Story } from '@/lib/story';

type Row = {
  slug: string;
  media_prefix: string | null;
  manifest: Story;
};

/**
 * 一篇已发布故事的 manifest，给 App 内的原生阅读器用。
 *
 * **App 不解析公开页的 HTML。** 页面结构随时会改，改一次所有装过 App 的人
 * 就同时瞎掉；manifest 是发布协议的一部分，本来就是稳定的。
 *
 * 比导出包里那份 story.json 多一个 `mediaBase`：服务器上图片不和 manifest
 * 放在一起，阅读器要知道相对路径该拼在谁后面。
 *
 * 可见性跟着公开页走：private 一律 404。**不做例外** ——
 * "我自己的故事我自己看"听起来合理，但那要求这个接口认令牌，
 * 于是一个公开只读的接口就变成了一个要鉴权的接口，不值得。
 */
export async function GET(
  _req: Request,
  { params }: { params: Promise<{ slug: string }> },
) {
  const { slug } = await params;
  const row = await one<Row>(
    `select slug, media_prefix, manifest
       from stories
      where slug = $1 and visibility <> 'private'
        and published_at is not null`,
    [slug],
  );
  if (!row) {
    return NextResponse.json({ error: 'NOT_FOUND' }, { status: 404 });
  }

  const base = (process.env.NEXT_PUBLIC_MEDIA_BASE ?? '').replace(/\/$/, '');
  const prefix = (row.media_prefix ?? `s/${row.slug}`).replace(/^\/|\/$/g, '');

  return NextResponse.json(
    { ...row.manifest, mediaBase: prefix ? `${base}/${prefix}` : base },
    {
      headers: {
        // 发布后 manifest 不再变（更新是整篇重发），短缓存足够挡住反复进出
        'Cache-Control': 'public, max-age=60, s-maxage=300',
      },
    },
  );
}
