import { decodePolyline, type Story } from './story';

/**
 * 把行程的路线画成一张矢量图（SVG path 的 d 属性 + 站点坐标）。
 *
 * 为什么不截地图: 分享预览图必须**在服务端稳定地生成出来**。
 * 去拉瓦片意味着依赖第三方、要等网络、可能超时 —— 而抓取器一旦拿到
 * 失败结果就会缓存住。路线本身是我们自己的数据，直接画反而更可靠，
 * 也更像一件作品而不是一张地图截图。
 *
 * 投影用 Web Mercator，和地图上看到的形状一致（纬度高的地方被拉长），
 * 不然同一条路线在预览图里和在网页上看是两个形状。
 */
export type RouteArt = {
  path: string;
  stops: { x: number; y: number }[];
  start: { x: number; y: number } | null;
  end: { x: number; y: number } | null;
};

const merc = (lat: number, lon: number): [number, number] => {
  const x = (lon + 180) / 360;
  const s = Math.sin((lat * Math.PI) / 180);
  const y = 0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI);
  return [x, y];
};

export function routeArt(
  story: Story,
  width: number,
  height: number,
  pad = 70,
): RouteArt | null {
  const lines = story.routes
    .map((r) => decodePolyline(r.geometry, r.precision ?? 6))
    .filter((pts) => pts.length > 1);
  const stopPts: [number, number][] =
    story.stops.map((s) => [s.lat, s.lon]);

  const all = [...lines.flat(), ...stopPts];
  if (all.length < 2) return null;

  const proj = all.map(([la, lo]) => merc(la, lo));
  const xs = proj.map((p) => p[0]);
  const ys = proj.map((p) => p[1]);
  const minX = Math.min(...xs); const maxX = Math.max(...xs);
  const minY = Math.min(...ys); const maxY = Math.max(...ys);
  // 等比缩放，别把路线拉变形
  const scale = Math.min(
    (width - pad * 2) / Math.max(maxX - minX, 1e-9),
    (height - pad * 2) / Math.max(maxY - minY, 1e-9),
  );
  const offX = (width - (maxX - minX) * scale) / 2;
  const offY = (height - (maxY - minY) * scale) / 2;
  const to = (la: number, lo: number) => {
    const [x, y] = merc(la, lo);
    return { x: (x - minX) * scale + offX, y: (y - minY) * scale + offY };
  };

  // 长路线抽稀，否则 path 长到几十 KB，渲染器会变慢
  const step = (n: number) => Math.max(1, Math.floor(n / 400));
  const path = lines.map((pts) => {
    const k = step(pts.length);
    const kept = pts.filter((_, i) => i % k === 0 || i === pts.length - 1);
    return kept
      .map((p, i) => {
        const { x, y } = to(p[0], p[1]);
        return `${i === 0 ? 'M' : 'L'}${x.toFixed(1)} ${y.toFixed(1)}`;
      })
      .join(' ');
  }).join(' ');

  const stops = story.stops.map((s) => to(s.lat, s.lon));
  return {
    path,
    stops,
    start: stops[0] ?? null,
    end: stops[stops.length - 1] ?? null,
  };
}
