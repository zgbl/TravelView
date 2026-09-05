'use client';

import { useEffect, useRef } from 'react';
import maplibregl from 'maplibre-gl';
import { decodePolyline, type Story } from '@/lib/story';

/**
 * 行程全览地图。
 *
 * 右侧那张跟着阅读走的地图回答的是"现在讲到哪儿了"，
 * 这一张回答的是**"我这趟一共走了哪儿"** —— 分享出去的时候，
 * 大多数人第一眼想看的就是它，所以它必须是页面里独立的一块，
 * 而不是藏在侧边栏里跟着滚。
 */
export default function StoryOverviewMap({ story }: { story: Story }) {
  const ref = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);

  useEffect(() => {
    if (!ref.current || mapRef.current || story.stops.length === 0) return;

    const tiles = process.env.NEXT_PUBLIC_MAP_TILES ??
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    const map = new maplibregl.Map({
      container: ref.current,
      style: {
        version: 8,
        sources: {
          base: {
            type: 'raster',
            tiles: [tiles],
            tileSize: 256,
            attribution: '&copy; OpenStreetMap contributors',
          },
        },
        layers: [{ id: 'base', type: 'raster', source: 'base' }],
      },
      center: [story.stops[0].lon, story.stops[0].lat],
      zoom: 3,
      attributionControl: false,
      // 滚轮留给页面，否则读者滚到这里就被地图卡住
      scrollZoom: false,
    });
    mapRef.current = map;
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }),
      'top-right');

    map.on('load', () => {
      const all: [number, number][] = [];
      const features = story.routes.map((r) => {
        const pts = decodePolyline(r.geometry, r.precision ?? 6);
        all.push(...pts);
        return {
          type: 'Feature' as const,
          properties: { flight: r.mode === 'flight' },
          geometry: {
            type: 'LineString' as const,
            coordinates: pts.map(([la, lo]) => [lo, la]),
          },
        };
      });

      // 相邻两站之间没有路线数据的地方，用虚线连上 ——
      // 地图上凭空断一截，读者只会以为产品坏了
      const has = new Set(story.routes.map((r) => `${r.from}>${r.to}`));
      const gapFeatures: GeoJSON.Feature<GeoJSON.LineString>[] = [];
      for (let i = 0; i + 1 < story.stops.length; i++) {
        const a = story.stops[i];
        const b = story.stops[i + 1];
        if (has.has(`${a.id}>${b.id}`)) continue;
        gapFeatures.push({
          type: 'Feature' as const,
          properties: {},
          geometry: {
            type: 'LineString' as const,
            coordinates: [[a.lon, a.lat], [b.lon, b.lat]],
          },
        });
      }
      if (gapFeatures.length) {
        map.addSource('gaps', {
          type: 'geojson',
          data: { type: 'FeatureCollection', features: gapFeatures },
        });
        map.addLayer({
          id: 'gaps',
          type: 'line',
          source: 'gaps',
          paint: {
            'line-color': '#8a9a98',
            'line-width': 2,
            'line-opacity': 0.5,
            'line-dasharray': [2, 3],
          },
        });
      }

      map.addSource('all-routes', {
        type: 'geojson',
        data: { type: 'FeatureCollection', features },
      });
      map.addLayer({
        id: 'all-routes',
        type: 'line',
        source: 'all-routes',
        paint: { 'line-color': '#4fbfa8', 'line-width': 4, 'line-opacity': 0.9 },
      });

      // 编号的站: 点一下就跳到正文对应的那一段
      story.stops.forEach((s, i) => {
        const pin = document.createElement('div');
        pin.textContent = String(i + 1);
        pin.title = s.name ?? `第 ${i + 1} 站`;
        pin.className =
          'flex h-7 w-7 cursor-pointer items-center justify-center ' +
          'rounded-full border-2 border-ink bg-accent text-xs font-semibold ' +
          'text-ink shadow-md';
        pin.addEventListener('click', () => {
          document
            .querySelector(`[data-stop="${s.id}"]`)
            ?.scrollIntoView({ behavior: 'smooth', block: 'center' });
        });
        new maplibregl.Marker({ element: pin })
          .setLngLat([s.lon, s.lat])
          .addTo(map);
        all.push([s.lat, s.lon]);
      });

      if (all.length) {
        const b = new maplibregl.LngLatBounds();
        all.forEach(([la, lo]) => b.extend([lo, la]));
        map.fitBounds(b, { padding: 60, duration: 0 });
      }
    });

    return () => {
      map.remove();
      mapRef.current = null;
    };
  }, [story]);

  return <div ref={ref} className="h-[min(70vh,680px)] w-full rounded-2xl
    border border-white/10 bg-ink" />;
}
