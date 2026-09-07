'use client';

import { useEffect, useRef } from 'react';
import maplibregl from 'maplibre-gl';
import { decodePolyline, type Story } from '@/lib/story';

/**
 * 片头的**真地图**。
 *
 * 关键决定: 底图一点都不压暗。要让标题读得清，就去处理标题
 * （下方一条局部渐变 + 文字阴影），而不是把整张地图糊掉 ——
 * 那样地图就不成其为地图了。
 *
 * 路线用两层画: 深色粗描边打底 + 亮青细线在上。
 * 这样无论底图是浅色街道、深色地形还是卫星影像，路线都跳得出来，
 * 不用为了迁就路线去挑底图。
 *
 * 不可交互（不缩放、不拖动）: 它是封面，不是工具。
 * 想动手的读者往下滚一屏就有那张能操作的「行程全览」。
 */
export default function HeroMap({
  story,
  /// 底部给标题留出的空间（像素）。路线会被推到上半屏，不被字压住
  bottomPad = 260,
}: {
  story: Story;
  bottomPad?: number;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);

  useEffect(() => {
    if (!ref.current || mapRef.current) return;

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
      center: [story.stops[0]?.lon ?? 0, story.stops[0]?.lat ?? 0],
      zoom: 3,
      attributionControl: false,
      interactive: false,
    });
    mapRef.current = map;

    map.on('load', () => {
      const all: [number, number][] = [];
      const features = story.routes.map((r) => {
        const pts = decodePolyline(r.geometry, r.precision ?? 6);
        all.push(...pts);
        return {
          type: 'Feature' as const,
          properties: {},
          geometry: {
            type: 'LineString' as const,
            coordinates: pts.map(([la, lo]) => [lo, la]),
          },
        };
      });

      map.addSource('route', {
        type: 'geojson',
        data: { type: 'FeatureCollection', features },
      });
      // 深色描边打底 —— 浅色街道图上也看得见
      map.addLayer({
        id: 'route-casing',
        type: 'line',
        source: 'route',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': '#0f1113', 'line-width': 9, 'line-opacity': 0.55,
        },
      });
      map.addLayer({
        id: 'route-line',
        type: 'line',
        source: 'route',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': '#4fbfa8', 'line-width': 4 },
      });

      const stops: GeoJSON.Feature[] = story.stops.map((s) => ({
        type: 'Feature',
        properties: {},
        geometry: { type: 'Point', coordinates: [s.lon, s.lat] },
      }));
      map.addSource('stops', {
        type: 'geojson',
        data: { type: 'FeatureCollection', features: stops },
      });
      map.addLayer({
        id: 'stops',
        type: 'circle',
        source: 'stops',
        paint: {
          'circle-radius': 4,
          'circle-color': '#ffffff',
          'circle-stroke-color': '#0f1113',
          'circle-stroke-width': 2,
        },
      });

      const pts = all.length ? all : story.stops.map((s) =>
        [s.lat, s.lon] as [number, number]);
      if (pts.length) {
        const b = pts.reduce(
          (acc, [la, lo]) => acc.extend([lo, la] as [number, number]),
          new maplibregl.LngLatBounds(
            [pts[0][1], pts[0][0]], [pts[0][1], pts[0][0]]),
        );
        // 底部多留出标题的高度，路线自然被推到上半屏
        map.fitBounds(b, {
          padding: { top: 70, right: 70, bottom: bottomPad, left: 70 },
          duration: 0,
        });
      }
    });

    return () => {
      map.remove();
      mapRef.current = null;
    };
  }, [story, bottomPad]);

  return <div ref={ref} className="h-full w-full bg-[#0c0e10]" />;
}
