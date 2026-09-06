import { ImageResponse } from 'next/og';
import { one } from '@/lib/db';
import { mediaUrl, miles, type Story } from '@/lib/story';

export const alt = 'TravelView Story';
export const size = { width: 1200, height: 630 };
export const contentType = 'image/png';

/**
 * 分享预览图。**这张图决定别人点不点。**
 *
 * 用封面照片打底 + 标题 + 四个数字，和结束卡片是同一套视觉。
 * 输出 PNG —— Facebook 与微信的抓取器都不认 WebP。
 */
export default async function Image(
  { params }: { params: { slug: string } },
) {
  const row = await one<{ title: string; subtitle: string | null;
    manifest: Story; slug: string; media_prefix: string | null }>(
    'select title, subtitle, manifest, slug, media_prefix from stories where slug = $1',
    [params.slug],
  );

  const title = row?.title ?? 'TravelView';
  // 老数据没有 media_prefix，退回它当年用的 s/<slug>
  const prefix = row ? (row.media_prefix ?? `s/${row.slug}`) : null;
  const stats = row?.manifest?.stats;
  const cover = row?.manifest?.cover
    ? row.manifest.photos.find((p) => p.id === row.manifest.cover)
    : undefined;

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
        {cover && (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={mediaUrl(cover.web.path, prefix)}
            alt=""
            style={{
              position: 'absolute', inset: 0, width: '100%', height: '100%',
              objectFit: 'cover', filter: 'brightness(0.55)',
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
