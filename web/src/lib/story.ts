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
export function mediaUrl(path: string, prefix?: string | null) {
  const base = (process.env.NEXT_PUBLIC_MEDIA_BASE ?? '').replace(/\/$/, '');
  const rel = path.replace(/^\//, '');
  const pre = (prefix ?? '').replace(/^\/|\/$/g, '');
  return pre ? `${base}/${pre}/${rel}` : `${base}/${rel}`;
}

export function miles(meters: number) {
  return Math.round(meters / 1609.344);
}
