import { ImageResponse } from 'next/og';
import { one } from '@/lib/db';
import { mediaUrl, miles, type Story } from '@/lib/story';
import { routeArt } from '@/lib/route-art';

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
  const m = row?.manifest as
    { ogImage?: string; coverMode?: string } | undefined;
  const wantsMap = m?.coverMode !== 'photo';   // 默认地图
  const ogPath = m?.ogImage;
  const photoBg = !wantsMap && ogPath && /\.jpe?g$/i.test(ogPath)
    ? mediaUrl(ogPath, prefix) : null;
  // 路线图在服务端直接画，不拉瓦片、不会超时、不依赖任何外部服务
  const art = row && wantsMap ? routeArt(row.manifest, size.width, size.height)
    : null;

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
        {art ? (
          <svg
            width={size.width}
            height={size.height}
            viewBox={`0 0 ${size.width} ${size.height}`}
            style={{ position: 'absolute', inset: 0 }}
          >
            <rect width={size.width} height={size.height} fill="#0f1113" />
            {/* 底下一条粗的暗线当"光晕"，上面一条亮线 —— 两条叠出发光感，
                比 filter 稳（satori 不支持滤镜） */}
            <path d={art.path} fill="none" stroke="#1f6f63"
              strokeWidth={14} strokeLinecap="round" strokeLinejoin="round"
              opacity={0.5} />
            <path d={art.path} fill="none" stroke="#4fbfa8"
              strokeWidth={5} strokeLinecap="round" strokeLinejoin="round" />
            {art.stops.map((p, i) => (
              <circle key={i} cx={p.x} cy={p.y} r={5}
                fill="#0f1113" stroke="#4fbfa8" strokeWidth={3} />
            ))}
            {art.end && (
              <circle cx={art.end.x} cy={art.end.y} r={9}
                fill="#ff8a5b" stroke="#0f1113" strokeWidth={3} />
            )}
          </svg>
        ) : photoBg ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={photoBg}
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
