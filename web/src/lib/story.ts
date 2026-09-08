/**
 * Story 类型与 polyline 解码。
 *
 * **和桌面端 tv_core 里的 story.dart 是同一份契约。**
 * 改这里就必须同步改那边，否则发布出去的 manifest 读不出来。
 */

export type StoryPhoto = {
  id: string;
  takenAt: string;
  lat?: number;
  lon?: number;
  web: { path: string; w: number; h: number };
  thumb?: string;
  caption?: string;
};

export type StoryStop = {
  /** 英文版标题和正文。没有就回落到 name/note */
  nameEn?: string;
  noteEn?: string;
  id: string;
  seq: number;
  name?: string;
  note?: string;
  lat: number;
  lon: number;
  arrive: string;
  leave: string;
  hero?: string;
  photos: string[];
};

export type StoryDay = { date: string; label?: string; stops: string[] };

export type StoryRoute = {
  from: string;
  to: string;
  mode: string;
  source: string;
  provider: string;
  distanceMeters: number;
  durationSeconds?: number;
  geometry: string;
  precision?: number;
};

export type Story = {
  version: number;
  id: string;
  slug: string;
  title: string;
  subtitle?: string;
  start: string;
  end: string;
  cover?: string;
  template: string;
  stats: {
    days: number;
    stops: number;
    photos: number;
    distanceMeters: number;
  };
  days: StoryDay[];
  stops: StoryStop[];
  photos: StoryPhoto[];
  routes: StoryRoute[];
};

/** 和 Dart 端 PolylineCodec 完全一致的解码 */
export function decodePolyline(str: string, precision = 6): [number, number][] {
  const factor = Math.pow(10, precision);
  let index = 0;
  let lat = 0;
  let lng = 0;
  const out: [number, number][] = [];
  while (index < str.length) {
    let b: number;
    let shift = 0;
    let result = 0;
    do {
      b = str.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += result & 1 ? ~(result >> 1) : result >> 1;
    shift = 0;
    result = 0;
    do {
      b = str.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += result & 1 ? ~(result >> 1) : result >> 1;
    out.push([lat / factor, lng / factor]);
  }
  return out;
}

/**
 * 图片地址 = 媒体根 + Story 前缀 + manifest 里的相对路径。
 *
 * manifest 里存的是 `photos/x.webp` 这样的**相对路径**，不带前缀 ——
 * 这样同一份 manifest 在本地预览、在导出包里、在服务器上都成立，
 * 前缀由发布时决定并记在 stories.media_prefix 里。
 */
/**
 * 列表和网格里该用哪张图。
 *
 * **缩略图（480px）优先。** 网格里一张图显示出来也就两三百像素宽，
 * 拿 1600px 的原图去填等于让每个访客白下几十兆 ——
 * 一篇 166 张照片的游记，网格全用大图就是 80MB 的首屏。
 * 点开大图时才换成 1600px 那张。
 */
export function thumbUrl(
  p: { web: { path: string }; thumb?: string },
  prefix?: string | null,
) {
  return mediaUrl(p.thumb ?? p.web.path, prefix);
}

export function mediaUrl(path: string, prefix?: string | null) {
  const base = (process.env.NEXT_PUBLIC_MEDIA_BASE ?? '').replace(/\/$/, '');
  const rel = path.replace(/^\//, '');
  const pre = (prefix ?? '').replace(/^\/|\/$/g, '');
  return pre ? `${base}/${pre}/${rel}` : `${base}/${rel}`;
}

export function miles(meters: number) {
  return Math.round(meters / 1609.344);
}

/**
 * 距离单位由**发布这篇游记的人**决定，写在 story.units 里。
 * 'auto' 时按第一站的经纬度粗判美国，其余用公里。
 *
 * 页面上的统计数字和站内解说必须用同一个单位 ——
 * 封面写 "1,240 MILES"、正文写"约 78 公里"，读者会以为数据是乱的。
 */
export function distUnit(story: Story): 'mi' | 'km' {
  const u = (story as unknown as { units?: string }).units;
  if (u === 'mi' || u === 'km') return u;
  const s = story.stops[0];
  if (!s) return 'km';
  const usa = s.lat >= 24.5 && s.lat <= 49 && s.lon >= -125 && s.lon <= -66.9;
  const ak = s.lat >= 51 && s.lat <= 71.5 && s.lon >= -170 && s.lon <= -129;
  const hi = s.lat >= 18.5 && s.lat <= 22.5 && s.lon >= -160.5 && s.lon <= -154.5;
  return usa || ak || hi ? 'mi' : 'km';
}

/// 按上面的单位换算出的数字
export function dist(meters: number, unit: 'mi' | 'km') {
  return Math.round(unit === 'mi' ? meters / 1609.344 : meters / 1000);
}

/// 统计栏上那个大写的单位名
export function distLabel(unit: 'mi' | 'km', locale: string) {
  if (locale === 'en') return unit === 'mi' ? 'MILES' : 'KM';
  return unit === 'mi' ? '英里' : '公里';
}
