'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import maplibregl from 'maplibre-gl';
import { decodePolyline, mediaUrl, dist, distUnit, distLabel, type Story }
  from '@/lib/story';
import { t, type Locale } from '@/lib/i18n';
import { Ambient, PLAYER_MUSIC } from '@/lib/ambient';
import { carSvg, bearing, smoothTurn } from '@/lib/carMarker';

/**
 * 全屏播放。
 *
 * 滚着看和**被放一遍**是两种体验: 前者要读者不停做决定（还要不要往下滚），
 * 后者只要求他坐着。一篇 160 张照片的游记，愿意从头滚到尾的人很少，
 * 愿意看完一段自动播放的人多得多。
 *
 * 一次播放由若干「拍子」(Beat) 组成:
 *   title    片头: 标题 + 四个数字
 *   transit  转场: 地图占屏，小车从上一站开到这一站，路线随之画出
 *   photo    一张照片全屏 + 缓慢推移(Ken Burns) + 文字入场
 *   end      片尾: 回到全程路线
 *
 * **转场是这个产品独有的东西**。别家的相册播放器只有照片切换，
 * 而这里每换一站，读者能看见自己走过的那段路 —— 这是"旅行"这件事的形状。
 */

type Beat =
  | { kind: 'title' }
  | { kind: 'transit'; stop: number }
  | { kind: 'photo'; stop: number; photoId: string; nth: number }
  | { kind: 'end' };

/** 每一拍停多久（毫秒）。转场要留够时间让人看清车开到哪儿了。 */
const DUR = { title: 4000, transit: 3600, photo: 4200, end: 6000 };

/** 播放时每站最多放几张。见文件末尾"为什么要限张数"。 */
const MAX_PER_STOP = 6;

export default function StoryPlayer({
  story, prefix, locale = 'zh', startStop = 0, onClose,
}: {
  story: Story;
  prefix?: string | null;
  locale?: Locale;
  /// 从第几站开始播。行程很长时，读者多半想从**正在看的这一站**接着看，
  /// 而不是回到片头重看一遍
  startStop?: number;
  onClose: () => void;
}) {
  const beats = useMemo<Beat[]>(() => {
    const out: Beat[] = [{ kind: 'title' }];
    story.stops.forEach((s, i) => {
      out.push({ kind: 'transit', stop: i });
      const ids = [
        ...(s.hero ? [s.hero] : []),
        ...s.photos.filter((p) => p !== s.hero),
      ].slice(0, MAX_PER_STOP);
      ids.forEach((photoId, nth) =>
        out.push({ kind: 'photo', stop: i, photoId, nth }));
    });
    out.push({ kind: 'end' });
    return out;
  }, [story]);

  /// 起始 beat: 落在指定那一站的转场上。**从转场开始而不是从照片开始** ——
  /// 先看小车开到这一站，才知道自己在地图的哪儿
  const startAt = useMemo(() => {
    if (!startStop) return 0;
    const at = beats.findIndex(
      (b) => b.kind === 'transit' && b.stop === startStop);
    return at < 0 ? 0 : at;
  }, [beats, startStop]);

  const [i, setI] = useState(startAt);
  const [playing, setPlaying] = useState(true);

  // ── 配乐 ──
  // 默认**不出声**。在办公室点开一篇游记，突然放起音乐，是会让人
  // 立刻关掉页面的那种体验；何况浏览器本来也不允许网页自己发声。
  // 记住用户的选择: 愿意开声音的人，不该每篇都点一次。
  const [sound, setSound] = useState(false);
  const ambientRef = useRef<Ambient | null>(null);
  useEffect(() => {
    const a = new Ambient();
    ambientRef.current = a;
    // 上次开过声音的人，这次直接接上。播放器是被"点播放"点开的，
    // 手势还在，start() 通常能过；被浏览器拦下也只是没声音，不报错
    let on = false;
    try { on = localStorage.getItem('tv.player.sound') === '1'; } catch { /* 无痕 */ }
    if (on) { setSound(true); void a.start(); }
    return () => { void a.stop(); };   // 退出播放器一定要停，淡出由 stop() 管
  }, []);
  const toggleSound = useCallback(() => {
    const a = ambientRef.current;
    if (!a) return;
    setSound((on) => {
      const next = !on;
      // 只在这个点击里 start() —— 用户手势之外调用会被浏览器拒掉
      if (next) void a.start(); else void a.stop();
      try { localStorage.setItem('tv.player.sound', next ? '1' : '0'); }
      catch { /* 无痕模式会抛，不要紧 */ }
      return next;
    });
  }, []);
  const beat = beats[i] ?? beats[0];
  const photoById = useMemo(
    () => Object.fromEntries(story.photos.map((p) => [p.id, p])), [story]);

  /**
   * 真·全屏（Fullscreen API），不是"铺满浏览器窗口"。
   *
   * 用户想看全屏播放时，会本能地去点浏览器的绿色按钮 —— 在 macOS 上
   * 那是"进入全屏"，系统会把窗口挪进一个新的 Space，画面向右滑走，
   * 看起来就像窗口跑丢了。**这件事不该让用户去跟浏览器较劲**:
   * 播放器自己申请全屏，地址栏、标签栏、Dock 一起消失，退出按 Esc。
   */
  const rootRef = useRef<HTMLDivElement>(null);
  const [full, setFull] = useState(false);

  const toggleFull = useCallback(() => {
    const el = rootRef.current;
    if (!el) return;
    if (document.fullscreenElement) {
      void document.exitFullscreen().catch(() => {});
    } else {
      // Safari 老版本要 webkit 前缀；拿不到就算了，窗口内播放照样能看
      const req = el.requestFullscreen?.bind(el) ??
        (el as unknown as { webkitRequestFullscreen?: () => Promise<void> })
          .webkitRequestFullscreen?.bind(el);
      void req?.()?.catch(() => {});
    }
  }, []);

  // **绝对不要自动进全屏。**
  // 在 macOS 上网页全屏和绿钮全屏是同一套机制: 系统会把窗口挪进一个新的
  // Space，画面向右滑走。用户没要求，画面就"跑丢"了，而全屏之后
  // 那个退出按钮他根本没机会去点 —— 屏幕已经不在眼前了。
  // 全屏只能由用户明确要求（F 键或右下角按钮），且必须随时能退出来。

  // 播放器关闭时一定要退出全屏，不能把浏览器留在全屏状态里
  useEffect(() => () => {
    if (document.fullscreenElement) void document.exitFullscreen().catch(() => {});
  }, []);

  useEffect(() => {
    const onFs = () => setFull(!!document.fullscreenElement);
    document.addEventListener('fullscreenchange', onFs);
    return () => document.removeEventListener('fullscreenchange', onFs);
  }, []);

  const go = useCallback((d: number) => {
    setI((prev) => Math.max(0, Math.min(beats.length - 1, prev + d)));
  }, [beats.length]);

  // ── 自动播放 ──
  const dur = DUR[beat.kind];
  useEffect(() => {
    if (!playing) return;
    if (i >= beats.length - 1) return;      // 片尾停住，不循环
    const id = setTimeout(() => go(1), dur);
    return () => clearTimeout(id);
  }, [i, playing, dur, go, beats.length]);

  // ── 键盘 ──
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      // **Esc 永远是出口，没有例外。**
      // 之前写成"全屏时 Esc 只退全屏、不关播放器"，结果是用户在一个
      // 已经滑走的窗口里按 Esc，什么都没发生 —— 一个逃不出去的界面
      // 是最糟的界面。现在 Esc 一次退到底: 退全屏，并关掉播放器。
      if (e.key === 'Escape') {
        if (document.fullscreenElement) void document.exitFullscreen().catch(() => {});
        onClose();
      }
      if (e.key === 'f' || e.key === 'F') toggleFull();
      if (e.key === 'ArrowRight' || e.key === ' ') { e.preventDefault(); go(1); }
      if (e.key === 'ArrowLeft') go(-1);
      if (e.key === 'p' || e.key === 'P') setPlaying((v) => !v);
    };
    window.addEventListener('keydown', onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = prev;
    };
  }, [go, onClose, toggleFull]);

  // 切到别的标签页就暂停 —— 没人看的时候还在跑，纯属浪费电和流量
  useEffect(() => {
    const onVis = () => { if (document.hidden) setPlaying(false); };
    document.addEventListener('visibilitychange', onVis);
    return () => document.removeEventListener('visibilitychange', onVis);
  }, []);

  // ── 预加载 ──
  // 不预载的话每张照片都要现下 200KB，播放会一顿一顿的
  useEffect(() => {
    for (let k = i + 1; k <= i + 3 && k < beats.length; k++) {
      const b = beats[k];
      if (b.kind !== 'photo') continue;
      const ph = photoById[b.photoId];
      if (!ph) continue;
      const img = new Image();
      img.src = mediaUrl(ph.web.path, prefix);
    }
  }, [i, beats, photoById, prefix]);

  // 到站时给一声，让"车在动"这件事也听得见
  useEffect(() => {
    if (sound && beat.kind === 'transit') ambientRef.current?.transit();
  }, [i, beat.kind, sound]);

  // 暂停时音乐跟着停 —— 画面停了声音还在飘，很怪
  useEffect(() => {
    const a = ambientRef.current;
    if (!a || !sound) return;
    if (playing) void a.start(); else void a.stop();
  }, [playing, sound]);

  const stop = beat.kind === 'photo' || beat.kind === 'transit'
    ? story.stops[beat.stop] : undefined;

  /* 点画面任意处 = 暂停/继续。
     前后翻页交给方向键和进度条 —— 一个全屏画面上，
     "点左边后退、点右边前进"没有任何可见提示，用户只会以为点坏了。
     暂停才是看照片时真正想做的事。 */
  return (
    <div
      ref={rootRef}
      className="fixed inset-0 z-[80] select-none overflow-hidden bg-black"
      onClick={() => setPlaying((v) => !v)}
    >
      <PlayerMap
        story={story}
        beat={beat}
        active={beat.kind === 'transit' || beat.kind === 'end'}
      />

      {beat.kind === 'photo' && (
        <PhotoBeat
          key={`${i}`}                       // key 变了才会重新播放动画
          src={mediaUrl(photoById[beat.photoId]?.web.path ?? '', prefix)}
          caption={beat.nth === 0
            ? (locale === 'en' ? stop?.nameEn ?? stop?.name : stop?.name)
            : undefined}
          sub={beat.nth === 0
            ? (locale === 'en' ? stop?.noteEn ?? stop?.note : stop?.note)
            : photoById[beat.photoId]?.caption}
          variant={beat.nth % 4}
          zoomIn={(beat.stop + beat.nth) % 2 === 0}
        />
      )}

      {beat.kind === 'title' && (
        <Card>
          <h1 className="animate-[tvUp_.9s_cubic-bezier(.2,.7,.2,1)_both]
            text-[clamp(34px,7vw,86px)] font-semibold leading-[1.05]
            tracking-tight">
            {story.title}
          </h1>
          {story.subtitle && (
            <p className="mt-4 animate-[tvUp_.9s_.15s_cubic-bezier(.2,.7,.2,1)_both]
              text-[clamp(14px,2vw,20px)] text-white/80">
              {story.subtitle}
            </p>
          )}
          <div className="mt-10 flex flex-wrap justify-center gap-10
            animate-[tvUp_.9s_.3s_cubic-bezier(.2,.7,.2,1)_both]">
            <Num n={story.stats.days} k="DAYS" />
            <Num n={story.stats.stops} k="STOPS" />
            <Num n={dist(story.stats.distanceMeters, distUnit(story))}
              k={distLabel(distUnit(story), locale)} />
            <Num n={story.stats.photos} k="PHOTOS" />
          </div>
        </Card>
      )}

      {beat.kind === 'transit' && stop && (
        // 转场: 地图在下面跑，这里只压一行地名
        <div className="pointer-events-none absolute inset-x-0 bottom-[14vh]
          flex flex-col items-center">
          <div className="animate-[tvUp_.8s_cubic-bezier(.2,.7,.2,1)_both]
            rounded-full bg-black/45 px-7 py-3 backdrop-blur">
            <span className="text-[clamp(20px,3.4vw,38px)] font-semibold">
              {(locale === 'en' ? stop.nameEn ?? stop.name : stop.name) ??
                `${beat.stop + 1}`}
            </span>
          </div>
        </div>
      )}

      {beat.kind === 'end' && (
        <Card>
          <p className="text-sm uppercase tracking-[0.3em] text-white/50">
            {t(locale, 'player.end')}
          </p>
          <h2 className="mt-4 text-[clamp(26px,5vw,56px)] font-semibold">
            {story.title}
          </h2>
          <div className="mt-8 flex flex-wrap justify-center gap-10">
            <Num n={story.stats.days} k="DAYS" />
            <Num n={story.stats.stops} k="STOPS" />
            <Num n={dist(story.stats.distanceMeters, distUnit(story))}
              k={distLabel(distUnit(story), locale)} />
          </div>
          <button
            onClick={(e) => { e.stopPropagation(); setI(0); setPlaying(true); }}
            className="mt-10 rounded-full border border-white/25 px-6 py-2
              text-sm hover:bg-white/10"
          >
            {t(locale, 'player.again')}
          </button>
        </Card>
      )}

      {/* 暂停时压一层，并把「继续 / 退出」摆到正中 ——
          暂停的人通常是想多看两眼，或者想走了，这两件事都该一眼看见 */}
      {!playing && (
        <div className="absolute inset-0 flex items-center justify-center
          gap-4 bg-black/45 backdrop-blur-[2px]">
          <button
            onClick={(e) => { e.stopPropagation(); setPlaying(true); }}
            className="flex items-center gap-3 rounded-full bg-white/95 px-7
              py-3.5 text-sm font-semibold text-ink hover:bg-white"
          >
            <span className="text-[11px]">▶</span>{t(locale, 'player.play')}
          </button>
          <button
            onClick={(e) => { e.stopPropagation(); onClose(); }}
            className="rounded-full border border-white/30 px-7 py-3.5
              text-sm text-white/90 hover:bg-white/10"
          >
            {t(locale, 'player.exit')}
          </button>
        </div>
      )}

      {/* ── 控件 ── 平时淡出，鼠标动一下才出来 */}
      <div className="absolute inset-x-0 top-0 flex items-center gap-3 px-5 py-4">
        <Progress beats={beats} i={i} dur={dur} playing={playing} />
      </div>

      <div
        className="absolute bottom-5 right-5 flex items-center gap-2"
        onClick={(e) => e.stopPropagation()}
      >
        <Ctrl onClick={() => setPlaying((v) => !v)}
          label={playing ? t(locale, 'player.pause') : t(locale, 'player.play')}>
          {playing ? '❚❚' : '▶'}
        </Ctrl>
        {/* 配乐还没有做，按钮就不出现 —— 点了没反应比没有更糟 */}
        {PLAYER_MUSIC && (
          <Ctrl onClick={toggleSound}
            label={sound ? t(locale, 'player.mute') : t(locale, 'player.unmute')}>
            <span className={sound ? '' : 'line-through opacity-60'}>♪</span>
          </Ctrl>
        )}
        <Ctrl onClick={toggleFull}
          label={full ? t(locale, 'player.windowed') : t(locale, 'player.full')}>
          {full ? '⤡' : '⛶'}
        </Ctrl>
        <Ctrl onClick={onClose} label={t(locale, 'player.exit')}>✕</Ctrl>
      </div>
    </div>
  );
}

/* ---------- 地图: 转场时的主角 ---------- */

function PlayerMap({
  story, beat, active,
}: { story: Story; beat: Beat; active: boolean }) {
  const ref = useRef<HTMLDivElement>(null);
  const mapRef = useRef<maplibregl.Map | null>(null);
  const markerRef = useRef<maplibregl.Marker | null>(null);
  const rafRef = useRef<number>(0);
  /// 整条路线的折线点（lat,lon）与逐点累计里程
  const ptsRef = useRef<[number, number][]>([]);
  const cumRef = useRef<number[]>([]);
  /// 每一站落在折线上的里程 —— 小车就在相邻两站的里程之间走
  const stopDistRef = useRef<number[]>([]);
  /// 车头当前朝向（度）。平滑转向要用上一帧的值
  const headRef = useRef<number>(0);

  useEffect(() => {
    if (!ref.current || mapRef.current) return;
    const tiles = process.env.NEXT_PUBLIC_MAP_TILES ??
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    const map = new maplibregl.Map({
      container: ref.current,
      style: {
        version: 8,
        sources: {
          base: { type: 'raster', tiles: [tiles], tileSize: 256 },
        },
        layers: [{ id: 'base', type: 'raster', source: 'base' }],
      },
      center: [story.stops[0]?.lon ?? 0, story.stops[0]?.lat ?? 0],
      zoom: 4,
      attributionControl: false,
      interactive: false,
      // **在 5K 屏上限制画布分辨率。** 默认会按 devicePixelRatio=2 铺满整屏，
      // 一张 10240×5760 的 WebGL 画布，光这一层就是几百 MB 显存；
      // 而这张图是被压暗当背景用的，多出来的分辨率一点也看不见
      maxCanvasSize: [4096, 4096],
      refreshExpiredTiles: false,
    });
    mapRef.current = map;

    map.on('load', () => {
      // 把所有 route 段首尾接成一条折线，并算出逐点累计里程。
      // **动画要沿真实道路走**，直线插值会让车从高速上飞过山头
      const all: [number, number][] = [];
      story.routes.forEach((r) => {
        decodePolyline(r.geometry, r.precision ?? 6).forEach((pt) => {
          const last = all[all.length - 1];
          if (!last || last[0] !== pt[0] || last[1] !== pt[1]) all.push(pt);
        });
      });
      ptsRef.current = all;
      const cum = [0];
      for (let k = 1; k < all.length; k++) {
        cum.push(cum[k - 1] + haversine(all[k - 1], all[k]));
      }
      cumRef.current = cum;
      // 每一站取折线上离它最近的那个点的里程
      stopDistRef.current = story.stops.map((st) => {
        let best = 0, bestD = Infinity;
        for (let k = 0; k < all.length; k++) {
          const dLat = all[k][0] - st.lat;
          const dLon = (all[k][1] - st.lon) * Math.cos((st.lat * Math.PI) / 180);
          const d = dLat * dLat + dLon * dLon;
          if (d < bestD) { bestD = d; best = k; }
        }
        return cum[best];
      });

      const feats = story.routes.map((r) => ({
        type: 'Feature' as const,
        properties: {},
        geometry: {
          type: 'LineString' as const,
          coordinates: decodePolyline(r.geometry, r.precision ?? 6)
            .map(([la, lo]) => [lo, la]),
        },
      }));
      map.addSource('route', {
        type: 'geojson', data: { type: 'FeatureCollection', features: feats },
      });
      map.addLayer({
        id: 'casing', type: 'line', source: 'route',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': '#0f1113', 'line-width': 10, 'line-opacity': .5 },
      });
      map.addLayer({
        id: 'line', type: 'line', source: 'route',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': '#4fbfa8', 'line-width': 4 },
      });

      // 已走过的部分单独高亮 —— 看得见"走了多少、还剩多少"
      map.addSource('traveled', {
        type: 'geojson',
        data: { type: 'Feature', properties: {},
          geometry: { type: 'LineString', coordinates: [] } },
      });
      map.addLayer({
        id: 'traveled', type: 'line', source: 'traveled',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': '#ff8a5b', 'line-width': 5 },
      });

      const el = document.createElement('div');
      el.innerHTML = carSvg(26);
      el.style.filter = 'drop-shadow(0 3px 6px rgba(0,0,0,.45))';
      const start = all[0] ?? [story.stops[0]?.lat ?? 0, story.stops[0]?.lon ?? 0];
      markerRef.current = new maplibregl.Marker({
        element: el,
        // **跟着地图转，不跟着屏幕。** pitch/bearing 变化时车要贴在路上
        rotationAlignment: 'map',
        pitchAlignment: 'map',
      })
        .setLngLat([start[1], start[0]])
        .addTo(map);
      if (all.length > 1) {
        headRef.current = bearing(all[0], all[1]);
        markerRef.current.setRotation(headRef.current);
      }
    });

    return () => { map.remove(); mapRef.current = null; };
  }, [story]);

  // 转场: 小车从上一站开到这一站，镜头跟着走
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    cancelAnimationFrame(rafRef.current);

    if (beat.kind === 'end') {
      const pts = story.stops.map((s) => [s.lon, s.lat] as [number, number]);
      if (pts.length) {
        const b = pts.reduce((acc, p) => acc.extend(p),
          new maplibregl.LngLatBounds(pts[0], pts[0]));
        map.fitBounds(b, { padding: 90, duration: 1600 });
      }
      return;
    }
    if (beat.kind !== 'transit') return;

    const to = story.stops[beat.stop];
    const from = story.stops[beat.stop - 1] ?? to;
    if (!to) return;

    const all = ptsRef.current;
    const cum = cumRef.current;
    const stopDist = stopDistRef.current;
    const usePath = all.length > 1 && stopDist.length > beat.stop;

    /// 里程 -> 折线上的坐标（同时给出它落在第几个点之后，好画已走的路）
    const at = (d: number): { pos: [number, number]; idx: number } => {
      let k = 1;
      while (k < cum.length - 1 && cum[k] < d) k++;
      const segLen = cum[k] - cum[k - 1];
      const f = segLen > 0 ? (d - cum[k - 1]) / segLen : 0;
      return {
        pos: [
          all[k - 1][0] + (all[k][0] - all[k - 1][0]) * f,
          all[k - 1][1] + (all[k][1] - all[k - 1][1]) * f,
        ],
        idx: k,
      };
    };

    const dFrom = usePath ? stopDist[beat.stop - 1] ?? 0 : 0;
    const dTo = usePath ? stopDist[beat.stop] : 0;

    // 先把镜头框住这一段，再让车走完它 —— 观众要先看见"要去哪"。
    // 框的是**这一段真实路线**的范围，不是两个站点的连线:
    // 一段绕山的路，只框两端会把大半条路甩出画面
    let b: maplibregl.LngLatBounds;
    if (usePath && dTo > dFrom) {
      const a0 = at(dFrom), a1 = at(dTo);
      b = new maplibregl.LngLatBounds(
        [a0.pos[1], a0.pos[0]], [a0.pos[1], a0.pos[0]]);
      for (let k = a0.idx; k <= a1.idx && k < all.length; k++) {
        b.extend([all[k][1], all[k][0]]);
      }
      b.extend([a1.pos[1], a1.pos[0]]);
    } else {
      b = new maplibregl.LngLatBounds([from.lon, from.lat],
        [from.lon, from.lat]).extend([to.lon, to.lat]);
    }
    map.fitBounds(b, { padding: 140, duration: 900, maxZoom: 11 });

    const traveled = map.getSource('traveled') as
      maplibregl.GeoJSONSource | undefined;
    const t0 = performance.now();
    const span = DUR.transit - 900;
    const tick = (now: number) => {
      const p = Math.max(0, Math.min(1, (now - t0 - 700) / span));
      // 缓入缓出，匀速看着像机器在拖
      const e = p < 0.5 ? 2 * p * p : 1 - ((-2 * p + 2) ** 2) / 2;
      if (usePath && dTo > dFrom) {
        const { pos, idx } = at(dFrom + (dTo - dFrom) * e);
        markerRef.current?.setLngLat([pos[1], pos[0]]);
        // 朝向取当前所在的那一小段折线的方向，再平滑地转过去
        const a = all[Math.max(0, idx - 1)];
        const b2 = all[Math.min(all.length - 1, idx)];
        if (a && b2 && (a[0] !== b2[0] || a[1] !== b2[1])) {
          headRef.current = smoothTurn(headRef.current, bearing(a, b2));
          markerRef.current?.setRotation(headRef.current);
        }
        traveled?.setData({
          type: 'Feature', properties: {},
          geometry: {
            type: 'LineString',
            coordinates: [...all.slice(0, idx), pos].map(([la, lo]) => [lo, la]),
          },
        });
      } else {
        // 这一段没有路线数据（比如飞过去的一程），只好直线过渡
        markerRef.current?.setLngLat([
          from.lon + (to.lon - from.lon) * e,
          from.lat + (to.lat - from.lat) * e,
        ]);
      }
      if (p < 1) rafRef.current = requestAnimationFrame(tick);
    };
    rafRef.current = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(rafRef.current);
  }, [beat, story]);

  return (
    <div
      className="absolute inset-0 transition-opacity duration-700"
      style={{ opacity: active ? 1 : 0 }}
    >
      <div ref={ref} className="h-full w-full" />
      {/* 半透明压一层: 地图是背景，压住之后上面的字才立得住 */}
      <div className="pointer-events-none absolute inset-0
        bg-gradient-to-t from-black/75 via-black/25 to-black/40" />
    </div>
  );
}

/* ---------- 照片 ---------- */

function PhotoBeat({
  src, caption, sub, variant, zoomIn,
}: {
  src: string; caption?: string | null; sub?: string | null;
  variant: number; zoomIn: boolean;
}) {
  // 文字入场的四种方式轮着来。**轮着来不是随机** ——
  // 随机会让同一站里两张连着用同一种，看着像卡住了
  const anim = [
    'animate-[tvUp_1s_.35s_cubic-bezier(.2,.7,.2,1)_both]',
    'animate-[tvIn_1.1s_.35s_cubic-bezier(.2,.7,.2,1)_both]',
    'animate-[tvWipe_1.1s_.35s_cubic-bezier(.2,.7,.2,1)_both]',
    'animate-[tvBlur_1.2s_.35s_ease-out_both]',
  ][variant];

  return (
    <>
      {/*
        竖图不裁: 背后放一张放大模糊的同一张图当底，比黑边体面得多。

        **模糊必须在一个很小的层上做，再放大。**
        原来是给整屏那么大的一层加 blur(40px) —— 在 5K 屏上等于让 GPU
        对一张 5120×2880 的位图做大半径卷积，每换一张照片重来一次，
        再叠上放大动画和地图的 WebGL 上下文，显存直接爆掉，
        Chrome 就把这个标签页杀了（把窗口最大化时必然触发）。
        现在这层只有 64×36，模糊半径也随之缩到 4px，效果一模一样，
        代价是原来的几千分之一。
      */}
      <div className="pointer-events-none absolute inset-0 overflow-hidden">
        <div
          className="absolute left-1/2 top-1/2 h-9 w-16 bg-cover bg-center
            opacity-45"
          style={{
            backgroundImage: `url(${src})`,
            filter: 'blur(4px)',
            // 放大到铺满，缩放发生在模糊之后，所以不增加卷积成本
            transform: 'translate(-50%,-50%) scale(90)',
            transformOrigin: 'center',
          }}
        />
      </div>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={src}
        alt=""
        className="absolute inset-0 h-full w-full object-contain"
        style={{
          animation: `${zoomIn ? 'tvKenIn' : 'tvKenOut'} 6s ease-out both`,
        }}
      />
      <div className="pointer-events-none absolute inset-x-0 bottom-0
        bg-gradient-to-t from-black/85 via-black/35 to-transparent
        px-[7vw] pb-[10vh] pt-[22vh]">
        {caption && (
          <h2 className={`text-[clamp(26px,5vw,56px)] font-semibold
            leading-tight tracking-tight ${anim}`}>
            {caption}
          </h2>
        )}
        {sub && (
          <p className="mt-3 max-w-[56ch] text-[clamp(13px,1.5vw,18px)]
            leading-relaxed text-white/85
            animate-[tvUp_1s_.6s_cubic-bezier(.2,.7,.2,1)_both]">
            {sub}
          </p>
        )}
      </div>
    </>
  );
}

/* ---------- 零件 ---------- */

function Card({ children }: { children: React.ReactNode }) {
  return (
    <div className="absolute inset-0 flex flex-col items-center justify-center
      px-[8vw] text-center">
      {children}
    </div>
  );
}

function Num({ n, k }: { n: number; k: string }) {
  return (
    <div>
      <div className="text-[clamp(22px,3vw,40px)] font-semibold">{n}</div>
      <div className="text-[11px] tracking-[0.18em] text-white/55">{k}</div>
    </div>
  );
}

function Ctrl({
  children, onClick, label,
}: { children: React.ReactNode; onClick: () => void; label: string }) {
  return (
    <button
      onClick={onClick}
      title={label}
      aria-label={label}
      className="flex h-10 w-10 items-center justify-center rounded-full
        bg-white/10 text-sm text-white/85 backdrop-blur hover:bg-white/20"
    >
      {children}
    </button>
  );
}

/** 顶部的分段进度条: 一段一拍，当前那段在走 */
function Progress({
  beats, i, dur, playing,
}: { beats: Beat[]; i: number; dur: number; playing: boolean }) {
  return (
    <div className="flex w-full gap-1">
      {beats.map((b, k) => (
        <div
          key={k}
          className={`h-[3px] flex-1 overflow-hidden rounded-full
            ${b.kind === 'transit' ? 'bg-accentBright/25' : 'bg-white/20'}`}
        >
          <div
            className="h-full bg-white"
            style={
              k < i
                ? { width: '100%' }
                : k === i
                  ? {
                      animation: `tvBar ${dur}ms linear both`,
                      animationPlayState: playing ? 'running' : 'paused',
                    }
                  : { width: 0 }
            }
          />
        </div>
      ))}
    </div>
  );
}


/// 两点间的大圆距离（米）。算里程用，精度足够
function haversine(a: [number, number], b: [number, number]) {
  const R = 6371000;
  const p1 = (a[0] * Math.PI) / 180;
  const p2 = (b[0] * Math.PI) / 180;
  const dp = p2 - p1;
  const dl = ((b[1] - a[1]) * Math.PI) / 180;
  const h = Math.sin(dp / 2) ** 2 +
    Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}
