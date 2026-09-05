'use client';

import { useEffect, useRef } from 'react';
import maplibregl from 'maplibre-gl';
import { decodePolyline, type Story } from '@/lib/story';

/**
 * 地图 + 小车。
 *
 * 效果的关键在于**滚动驱动**而不是自动播放:
 * 滚到哪一天，车就开到哪一天，走过的路线逐渐画出来。
 * 这把故事的时间线和地图的时间线绑成了一件事。
 *
 * 瓦片地址来自环境变量 —— 上线前换成自托管的 Protomaps，
 * 既符合 OSM 的使用政策，也不把访客的浏览行踪送给第三方。
 */
export default function StoryMap({
  story,
  progress,
  activeStop,
  activePhoto,
}: {
  story: Story;
  progress: number;
  activeStop?: string | null;
  /// 读者正在看的那张照片。指出它拍摄的位置 ——
  /// "这张是在哪拍的"是看游记时最常冒出来的问题。
  activePhoto?: string | null;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const carRef = useRef<maplibregl.Marker | null>(null);
  const pointsRef = useRef<[number, number][]>([]);
  const cumRef = useRef<number[]>([]);
  const pinRef = useRef<maplibregl.Marker | null>(null);

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
      zoom: 4,
      attributionControl: false,
      scrollZoom: false,
    });
    mapRef.current = map;

    map.on('load', () => {
      // 全部路线，浅色
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

      map.addSource('routes', {
        type: 'geojson',
        data: { type: 'FeatureCollection', features },
      });
      map.addLayer({
        id: 'routes',
        type: 'line',
        source: 'routes',
        paint: {
          'line-color': '#7d8f8d',
          'line-width': 3,
          'line-opacity': 0.55,
          'line-dasharray': [2, 2],
        },
        filter: ['==', ['get', 'flight'], true],
      });
      map.addLayer({
        id: 'routes-solid',
        type: 'line',
        source: 'routes',
        paint: { 'line-color': '#7d8f8d', 'line-width': 3, 'line-opacity': 0.5 },
        filter: ['==', ['get', 'flight'], false],
      });

      // 走过的那一段
      map.addSource('traveled', {
        type: 'geojson',
        data: {
          type: 'Feature',
          properties: {},
          geometry: { type: 'LineString', coordinates: [] },
        },
      });
      map.addLayer({
        id: 'traveled',
        type: 'line',
        source: 'traveled',
        paint: { 'line-color': '#4fbfa8', 'line-width': 5 },
      });

      // 站点
      map.addSource('stops', {
        type: 'geojson',
        data: {
          type: 'FeatureCollection',
          features: story.stops.map((s) => ({
            type: 'Feature' as const,
            properties: { id: s.id },
            geometry: { type: 'Point' as const, coordinates: [s.lon, s.lat] },
          })),
        },
      });
      map.addLayer({
        id: 'stops',
        type: 'circle',
        source: 'stops',
        paint: {
          'circle-radius': 5,
          'circle-color': '#4fbfa8',
          'circle-stroke-color': '#ffffff',
          'circle-stroke-width': 2,
        },
      });

      pointsRef.current = all;
      const cum = [0];
      for (let i = 1; i < all.length; i++) {
        cum.push(cum[i - 1] + haversine(all[i - 1], all[i]));
      }
      cumRef.current = cum;

      if (all.length > 1) {
        const el = document.createElement('div');
        el.className = 'text-2xl leading-none drop-shadow';
        el.textContent = '🚗';
        carRef.current = new maplibregl.Marker({ element: el })
          .setLngLat([all[0][1], all[0][0]])
          .addTo(map);

        const bounds = all.reduce(
          (b, [la, lo]) => b.extend([lo, la] as [number, number]),
          new maplibregl.LngLatBounds(
            [all[0][1], all[0][0]],
            [all[0][1], all[0][0]],
          ),
        );
        map.fitBounds(bounds, { padding: 60, duration: 0 });
      }
    });

    return () => {
      map.remove();
      mapRef.current = null;
    };
  }, [story]);

  // 进度 -> 小车位置 + 已走路线
  useEffect(() => {
    const map = mapRef.current;
    const all = pointsRef.current;
    const cum = cumRef.current;
    if (!map || !map.isStyleLoaded() || all.length < 2) return;

    const total = cum[cum.length - 1];
    const target = total * Math.max(0, Math.min(1, progress));
    let i = 1;
    while (i < cum.length - 1 && cum[i] < target) i++;
    const segLen = cum[i] - cum[i - 1];
    const t = segLen > 0 ? (target - cum[i - 1]) / segLen : 0;
    const pos: [number, number] = [
      all[i - 1][0] + (all[i][0] - all[i - 1][0]) * t,
      all[i - 1][1] + (all[i][1] - all[i - 1][1]) * t,
    ];

    const src = map.getSource('traveled') as maplibregl.GeoJSONSource | undefined;
    src?.setData({
      type: 'Feature',
      properties: {},
      geometry: {
        type: 'LineString',
        coordinates: [...all.slice(0, i), pos].map(([la, lo]) => [lo, la]),
      },
    });

    if (carRef.current) {
      carRef.current.setLngLat([pos[1], pos[0]]);
      const el = carRef.current.getElement();
      // 车头跟着道路方向转，不是横着滑
      el.style.transform += ` rotate(${bearing(all[i - 1], all[i]) - 90}deg)`;
    }
  }, [progress]);

  // 指出当前这张照片拍摄的位置
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    const ph = story.photos.find((p) => p.id === activePhoto);
    if (!ph || ph.lat == null || ph.lon == null) {
      pinRef.current?.remove();
      pinRef.current = null;
      return;
    }
    if (!pinRef.current) {
      const el = document.createElement('div');
      el.className =
        'h-4 w-4 rounded-full border-2 border-white bg-[#ff8a5b] shadow';
      pinRef.current = new maplibregl.Marker({ element: el })
        .setLngLat([ph.lon, ph.lat])
        .addTo(map);
    } else {
      pinRef.current.setLngLat([ph.lon, ph.lat]);
    }
    map.easeTo({ center: [ph.lon, ph.lat], duration: 500 });
  }, [activePhoto, story.photos]);

  // 滚到某一站，地图轻轻跟过去
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !activeStop) return;
    const s = story.stops.find((x) => x.id === activeStop);
    if (s) map.easeTo({ center: [s.lon, s.lat], duration: 900 });
  }, [activeStop, story.stops]);

  return <div ref={ref} className="h-full w-full bg-[#0c0e10]" />;
}

function haversine(a: [number, number], b: [number, number]) {
  const R = 6371008.8;
  const r = Math.PI / 180;
  const dLat = (b[0] - a[0]) * r;
  const dLon = (b[1] - a[1]) * r;
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(a[0] * r) * Math.cos(b[0] * r) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.atan2(Math.sqrt(s), Math.sqrt(1 - s));
}

function bearing(a: [number, number], b: [number, number]) {
  const r = Math.PI / 180;
  const y = Math.sin((b[1] - a[1]) * r) * Math.cos(b[0] * r);
  const x =
    Math.cos(a[0] * r) * Math.sin(b[0] * r) -
    Math.sin(a[0] * r) * Math.cos(b[0] * r) * Math.cos((b[1] - a[1]) * r);
  return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
}
