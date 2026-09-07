import { ImageResponse } from 'next/og';
import { one } from '@/lib/db';
import { mediaUrl, miles, type Story } from '@/lib/story';

export const alt = 'TravelView Story';
export const size = { width: 1200, height: 630 };
export const contentType = 'image/png';

/**
 * 分享预览图。**这张图决定别人点不点。**
 *
 * 两个坑，都踩过:
 *
 * 1. **next/og 不认 WebP。** 它底层是 satori + resvg，只解 PNG/JPEG。
 *    直接把我们的 WebP 派生图塞进 <img>，整个接口抛异常 → 500，
 *    Facebook 那边就是一大块白。所以这里只用导出时专门生成的
 *    `og.jpg`（见 story_exporter），没有它就退回纯文字卡片。
 * 2. **Next 15 的 params 是 Promise。** 不 await 拿到的是 undefined，
 *    查不到 story，卡片上只剩一个通用标题。
 *
 * 无论哪一步出问题，都必须**返回一张图**而不是 500 ——
 * 抓取器拿到 500 就会缓存失败结果，之后再分享还是白的。
 */
export default async function Image(
  { params }: { params: Promise<{ slug: string }> },
) {
  const { slug } = await params;

  let row: {
    title: string; subtitle: string | null; manifest: Story;
    slug: string; media_prefix: string | null;
  } | null = null;
  try {
    row = await one(
      `select title, subtitle, manifest, slug, media_prefix
         from stories where slug = $1 and visibility <> 'private'`, [slug]);
  } catch {
    row = null;
  }

  const title = row?.title ?? 'TravelView';
  const stats = row?.manifest?.stats;
  // 老数据没有 media_prefix，退回它当年用的 s/<slug>
  const prefix = row ? (row.media_prefix ?? `s/${row.slug}`) : null;
  // 只认 og.jpg。WebP 会让 satori 直接抛异常
  const ogPath = (row?.manifest as { ogImage?: string } | undefined)?.ogImage;
  const bg = ogPath && /\.jpe?g$/i.test(ogPath)
    ? mediaUrl(ogPath, prefix) : null;

  return new ImageResponse(
    (
      <div
        style={{
          width: '100%', height: '100%', display: 'flex',
          flexDirection: 'column', justifyContent: 'flex-end',
          background: '#0f1113', color: '#f2f0ec', position: 'relative',
          fontFamily: 'sans-serif',
        }}
      >
        {bg ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={bg}
            alt=""
            style={{
              position: 'absolute', inset: 0, width: '100%', height: '100%',
              objectFit: 'cover', filter: 'brightness(0.55)',
            }}
          />
        ) : (
          // 没有 og.jpg 时的兜底: 一块有层次的深色，比纯黑体面
          <div
            style={{
              position: 'absolute', inset: 0,
              background:
                'linear-gradient(135deg, #12312e 0%, #0f1113 55%, #17322f 100%)',
            }}
          />
        )}
        <div style={{ position: 'relative', padding: '0 64px 56px' }}>
          <div style={{ fontSize: 62, fontWeight: 700, letterSpacing: -1.5 }}>
            {title}
          </div>
          {row?.subtitle && (
            <div style={{ fontSize: 26, marginTop: 10, opacity: 0.85 }}>
              {row.subtitle}
            </div>
          )}
          {stats && (
            <div style={{ display: 'flex', gap: 44, marginTop: 30, fontSize: 22 }}>
              <span>{stats.days} days</span>
              <span>{stats.stops} stops</span>
              <span>{miles(stats.distanceMeters)} miles</span>
              <span>{stats.photos} photos</span>
            </div>
          )}
        </div>
      </div>
    ),
    size,
  );
}
