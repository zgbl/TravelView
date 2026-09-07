'use client';

import { useEffect, useRef, useState } from 'react';
import maplibregl from 'maplibre-gl';
import { carSvg, bearing as bearingOf, smoothTurn } from '@/lib/carMarker';
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
  stopAt,
  activeStop,
  activePhoto,
}: {
  story: Story;
  /// 读者正在看第几站、这一站滚过了多少（0-1）。
  /// **不要传"页面滚动百分比"** —— 见下面 stopDist 那段注释。
  stopAt: { index: number; frac: number };
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
  /// 每一站在路线上的里程位置（沿路线的累计距离）
  const stopDistRef = useRef<number[]>([]);
  /// 车头当前朝向（度）—— 平滑转向要记住上一次的值
  const carHeadRef = useRef<number>(0);
  const pinRef = useRef<maplibregl.Marker | null>(null);
  /// 读者自己缩放/拖动过地图了吗。true 之后不再自动跟随镜头
  const userMovedRef = useRef(false);
  /// 把镜头拉回整条路线。建图时装上，"回到路线"按钮用
  const fitAllRef = useRef<(() => void) | null>(null);

  /**
   * 定位点的大小。**这是给读者的选项，不是常量。**
   * 在手机小屏上 8px 的点几乎看不见，在 5K 屏上又嫌小；
   * 而且视力和使用距离因人而异，没有一个尺寸对所有人都对。
   * 存 localStorage: 这是这台设备上这个读者的偏好，不是作品的一部分。
   */
  const [pinScale, setPinScale] = useState(1);
  /// 定位点长什么样: 'dot' 橙色圆点 / 'car' 小车。也是读者的偏好
  const [pinShape, setPinShape] = useState<'dot' | 'car'>('dot');
  /// 控件是命令式建出来的（maplibre 的 IControl），
  /// 用 ref 把回调和那个示例小圆点接回 React 状态
  const pinShapeBtnRef = useRef<HTMLButtonElement | null>(null);
  const pinIconsRef = useRef<{ car: string; dot: string } | null>(null);
  const changePinRef = useRef<(d: number) => void>(() => {});
  useEffect(() => {
    try {
      const v = Number(localStorage.getItem('tv.pinScale'));
      if (v >= 0.6 && v <= 3) setPinScale(v);
      if (localStorage.getItem('tv.pinShape') === 'car') setPinShape('car');
    } catch {
      // 隐私模式 / 禁用了站点数据: 用默认值，不该因此报错
    }
  }, []);
  const changePin = (delta: number) => {
    setPinScale((prev) => {
      const n = Math.round(Math.max(0.6, Math.min(3, prev + delta)) * 10) / 10;
      try { localStorage.setItem('tv.pinScale', String(n)); } catch { /* 同上 */ }
      return n;
    });
  };
  changePinRef.current = changePin;

  const togglePinShape = () => {
    setPinShape((prev) => {
      const next = prev === 'dot' ? 'car' : 'dot';
      try { localStorage.setItem('tv.pinShape', next); } catch { /* 同上 */ }
      return next;
    });
  };
  const toggleShapeRef = useRef<() => void>(() => {});
  toggleShapeRef.current = togglePinShape;

  // 控件里那个示例小圆点跟着变
  // 形状按钮上画的是**切换之后会变成的样子**，所见即所得
  useEffect(() => {
    const btn = pinShapeBtnRef.current;
    const icons = pinIconsRef.current;
    if (btn && icons) {
      btn.innerHTML = pinShape === 'car' ? icons.dot : icons.car;
    }
  }, [pinShape]);

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
      // 鼠标滚轮 / 触控板双指缩放。地图是右半屏的 sticky 面板，
      // 左半边照样能滚动正文，所以不必为了保住页面滚动而牺牲地图操作。
      scrollZoom: true,
      doubleClickZoom: true,
      touchZoomRotate: true,
      dragPan: true,
      keyboard: false,
    });
    mapRef.current = map;

    // **放右上，不放右下**: 右下被固定在视口底部的分享条压着，
    // 按钮会被那层渐变糊掉一半，点击也被它截走
    map.addControl(
      new maplibregl.NavigationControl({ showCompass: true, showZoom: true }),
      'top-right');

    // 读者自己动过地图之后，就别再把镜头抢回去了 ——
    // 正在放大看某条街，结果一滚动就被拽走，是最恼人的体验
    const markUserMoved = () => { userMovedRef.current = true; };
    map.on('dragstart', markUserMoved);
    map.on('zoomstart', (e) => {
      // 只认用户自己的操作，程序调用 easeTo 触发的不算
      if ((e as { originalEvent?: unknown }).originalEvent) markUserMoved();
    });
    map.on('wheel', markUserMoved);

    /**
     * 自定义控件。
     *
     * **必须长得和 maplibre 自带的一模一样**: 同一列、同样 29px 见方、
     * 竖排、深色图标。之前用横排 flex + 纯文本字符，结果既插在那一列里
     * 错位，字符（⤢）在有些系统字体里干脆没有字形，显示成一片白。
     * 图标一律用内联 SVG —— 不依赖任何字体。
     */
    const ctrlBtn = (title: string, svg: string, onClick: () => void) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.title = title;
      b.setAttribute('aria-label', title);
      b.innerHTML = svg;
      b.style.cssText =
        'display:flex;align-items:center;justify-content:center;color:#33393d';
      b.onclick = onClick;
      return b;
    };

    const group = (children: HTMLElement[]) => {
      const g = document.createElement('div');
      g.className = 'maplibregl-ctrl maplibregl-ctrl-group';
      children.forEach((c) => g.appendChild(c));
      return g;
    };

    const ICON = {
      // 四角箭头: 回到整条路线
      fit: '<svg width="15" height="15" viewBox="0 0 24 24" fill="none"' +
        ' stroke="currentColor" stroke-width="2" stroke-linecap="round">' +
        '<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/></svg>',
      bigger: '<svg width="15" height="15" viewBox="0 0 24 24">' +
        '<circle cx="12" cy="12" r="7" fill="currentColor"/></svg>',
      smaller: '<svg width="15" height="15" viewBox="0 0 24 24">' +
        '<circle cx="12" cy="12" r="3.2" fill="currentColor"/></svg>',
      car: '<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">' +
        '<path d="M5 11l1.5-4.5A2 2 0 0 1 8.4 5h7.2a2 2 0 0 1 1.9 1.5L19 11h.5' +
        'a1.5 1.5 0 0 1 1.5 1.5V17h-2v1.5a1.5 1.5 0 0 1-3 0V17H8v1.5' +
        'a1.5 1.5 0 0 1-3 0V17H3v-4.5A1.5 1.5 0 0 1 4.5 11H5zm2.1 0h9.8l-1.1-3.3' +
        'a.5.5 0 0 0-.5-.4H8.7a.5.5 0 0 0-.5.4L7.1 11zM6.5 13a1.2 1.2 0 1 0 0 2.4' +
        ' 1.2 1.2 0 0 0 0-2.4zm11 0a1.2 1.2 0 1 0 0 2.4 1.2 1.2 0 0 0 0-2.4z"/></svg>',
      dot: '<svg width="16" height="16" viewBox="0 0 24 24">' +
        '<circle cx="12" cy="12" r="6" fill="#ff8a5b" stroke="#fff"' +
        ' stroke-width="2.5"/></svg>',
    };

    // 第一组: 回到整条路线
    const backBtn = ctrlBtn('回到路线', ICON.fit, () => {
      userMovedRef.current = false;
      fitAllRef.current?.();
    });
    map.addControl({
      onAdd: () => group([backBtn]),
      onRemove: () => {},
    } as maplibregl.IControl, 'top-right');

    // 第二组: 定位点的大小和形状。竖排三个，和缩放那一组同宽
    const shapeBtn = ctrlBtn('圆点 / 小车', ICON.car,
      () => toggleShapeRef.current());
    pinShapeBtnRef.current = shapeBtn;
    map.addControl({
      onAdd: () => group([
        ctrlBtn('定位点调大', ICON.bigger, () => changePinRef.current(0.4)),
        ctrlBtn('定位点调小', ICON.smaller, () => changePinRef.current(-0.4)),
        shapeBtn,
      ]),
      onRemove: () => {},
    } as maplibregl.IControl, 'top-right');
    pinIconsRef.current = ICON;

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
        // 俯视的车，按行进方向转头。**不能用 🚗 emoji** ——
        // 它是侧视的、永远朝左，往东开的时候看着像在倒车
        const el = document.createElement('div');
        el.innerHTML = carSvg(24);
        el.style.filter = 'drop-shadow(0 3px 6px rgba(0,0,0,.4))';
        carRef.current = new maplibregl.Marker({
          element: el,
          rotationAlignment: 'map',
          pitchAlignment: 'map',
        })
          .setLngLat([all[0][1], all[0][0]])
          .addTo(map);
        if (all.length > 1) {
          carHeadRef.current = bearingOf(all[0], all[1]);
          carRef.current.setRotation(carHeadRef.current);
        }

        const bounds = all.reduce(
          (b, [la, lo]) => b.extend([lo, la] as [number, number]),
          new maplibregl.LngLatBounds(
            [all[0][1], all[0][0]],
            [all[0][1], all[0][0]],
          ),
        );
        fitAllRef.current = () =>
          map.fitBounds(bounds, { padding: 60, duration: 600 });
        map.fitBounds(bounds, { padding: 60, duration: 0 });
      }
    });

    return () => {
      map.remove();
      mapRef.current = null;
    };
  }, [story]);

  /**
   * 把"第几站 + 段内比例"换算成路线上的里程。
   *
   * 每一站先找出它在路线折线上最近的那个点，记下该点的累计里程；
   * 小车就在相邻两站的里程之间插值。这样**小车永远停在读者正在看的那一站**。
   *
   * 之前是拿页面滚动百分比直接乘总里程 —— 一个有二十几张照片的城市
   * 要滚很久却只走了几英里，一段几百英里的高速可能一屏就过去了，
   * 两者对不上，车就飘到别的地方去了。
   */
  useEffect(() => {
    const all = pointsRef.current;
    const cum = cumRef.current;
    if (all.length < 2) return;
    stopDistRef.current = story.stops.map((st) => {
      let best = 0;
      let bestD = Infinity;
      for (let i = 0; i < all.length; i++) {
        const dLat = all[i][0] - st.lat;
        const dLon = (all[i][1] - st.lon) *
          Math.cos((st.lat * Math.PI) / 180);
        const d = dLat * dLat + dLon * dLon;
        if (d < bestD) { bestD = d; best = i; }
      }
      return cum[best];
    });
  }, [story]);

  // 当前站 -> 小车位置 + 已走路线
  useEffect(() => {
    const map = mapRef.current;
    const all = pointsRef.current;
    const cum = cumRef.current;
    const stopDist = stopDistRef.current;
    if (!map || !map.isStyleLoaded() || all.length < 2) return;

    const total = cum[cum.length - 1];
    let target: number;
    if (stopDist.length === 0) {
      target = 0;
    } else {
      const i = Math.max(0, Math.min(stopDist.length - 1, stopAt.index));
      const here = stopDist[i];
      // 最后一站之后没有"下一站"，就停在终点
      const next = i + 1 < stopDist.length ? stopDist[i + 1] : total;
      const f = Math.max(0, Math.min(1, stopAt.frac));
      target = here + (next - here) * f;
    }
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
      // 车头跟着道路方向转。**用 marker 的 rotation，不要动 transform** ——
      // maplibre 每帧都会重写 element 的 transform，往上追加只会越叠越歪
      const a = all[i - 1], b = all[i];
      if (a && b && (a[0] !== b[0] || a[1] !== b[1])) {
        carHeadRef.current = smoothTurn(carHeadRef.current, bearingOf(a, b), 0.5);
        carRef.current.setRotation(carHeadRef.current);
      }
    }
  }, [stopAt, story.stops]);

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
    const size = Math.round(16 * pinScale);
    if (!pinRef.current) {
      pinRef.current = new maplibregl.Marker({
        element: document.createElement('div'),
      }).setLngLat([ph.lon, ph.lat]).addTo(map);
    }
    // 圆点还是小车。**每次都重设样式**，因为读者可以随时切换形状
    const el = pinRef.current.getElement();
    if (pinShape === 'car') {
      // 用 SVG 而不是 emoji: emoji 在不同系统上长得完全不一样，
      // 而且颜色不受控，压在浅色地图上经常看不清
      const px = Math.round(24 * pinScale);
      el.className = '';
      el.style.cssText =
        `width:${px}px;height:${px}px;color:#ff8a5b;` +
        'filter:drop-shadow(0 1px 2px rgba(0,0,0,.55))';
      el.innerHTML = (pinIconsRef.current?.car ?? '')
        .replace('width="16"', `width="${px}"`)
        .replace('height="16"', `height="${px}"`);
    } else {
      el.innerHTML = '';
      el.className = 'rounded-full border-2 border-white bg-[#ff8a5b] shadow';
      el.style.cssText = `width:${size}px;height:${size}px`;
    }
    pinRef.current.setLngLat([ph.lon, ph.lat]);

    /**
     * **只在点跑出画面时才动镜头。**
     *
     * 原来是每换一张照片就 easeTo 一次，读者放大看某条街时会被反复拽走；
     * 后来改成"用户动过就再也不跟"，又变成点跑出屏幕得自己去找。
     * 正确的行为是电视转播里的跟拍: 主体在画面里就不动机位，
     * 快出画了才推一下，而且**保持读者自己调好的缩放级别**。
     */
    const b = map.getBounds();
    const w = b.getEast() - b.getWest();
    const h = b.getNorth() - b.getSouth();
    // 留 18% 的安全边: 贴着边缘也算"快出去了"，等真出去就晚了
    const inside =
      ph.lon > b.getWest() + w * 0.18 && ph.lon < b.getEast() - w * 0.18 &&
      ph.lat > b.getSouth() + h * 0.18 && ph.lat < b.getNorth() - h * 0.18;
    if (!inside) {
      map.easeTo({ center: [ph.lon, ph.lat], duration: 600 });
    }
  }, [activePhoto, story.photos, pinScale, pinShape]);

  // 滚到某一站，地图轻轻跟过去
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !activeStop) return;
    const s = story.stops.find((x) => x.id === activeStop);
    if (!s) return;
    // 同样的跟拍规则: 这一站在画面里就不动镜头
    const b = map.getBounds();
    const w = b.getEast() - b.getWest();
    const h = b.getNorth() - b.getSouth();
    const inside =
      s.lon > b.getWest() + w * 0.15 && s.lon < b.getEast() - w * 0.15 &&
      s.lat > b.getSouth() + h * 0.15 && s.lat < b.getNorth() - h * 0.15;
    if (!inside) map.easeTo({ center: [s.lon, s.lat], duration: 900 });
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

