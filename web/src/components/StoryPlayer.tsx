'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import maplibregl from 'maplibre-gl';
import { decodePolyline, mediaUrl, miles, type Story } from '@/lib/story';
import { t, type Locale } from '@/lib/i18n';
import { Ambient } from '@/lib/ambient';

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
  story, prefix, locale = 'zh', onClose,
}: {
  story: Story;
  prefix?: string | null;
  locale?: Locale;
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

  const [i, setI] = useState(0);
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
      if (e.key === 'Escape') onClose();
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
  }, [go, onClose]);

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

  return (
    <div
      className="fixed inset-0 z-[80] select-none overflow-hidden bg-black"
      onClick={(e) => {
        // 左三分之一后退，其余前进 —— 手机上不用找按钮
        const x = e.clientX / window.innerWidth;
        go(x < 0.33 ? -1 : 1);
      }}
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
            <Num n={miles(story.stats.distanceMeters)} k="MILES" />
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
            <Num n={miles(story.stats.distanceMeters)} k="MILES" />
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
        <Ctrl onClick={toggleSound}
          label={sound ? t(locale, 'player.mute') : t(locale, 'player.unmute')}>
          <span className={sound ? '' : 'line-through opacity-60'}>♪</span>
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
    });
    mapRef.current = map;

    map.on('load', () => {
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

      const el = document.createElement('div');
      el.style.cssText =
        'width:18px;height:18px;border-radius:999px;background:#ff8a5b;' +
        'border:3px solid #fff;box-shadow:0 2px 10px rgba(0,0,0,.5)';
      markerRef.current = new maplibregl.Marker({ element: el })
        .setLngLat([story.stops[0]?.lon ?? 0, story.stops[0]?.lat ?? 0])
        .addTo(map);
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

    // 先把镜头框住这一段，再让点走完它 —— 观众要先看见"要去哪"
    const b = new maplibregl.LngLatBounds([from.lon, from.lat],
      [from.lon, from.lat]).extend([to.lon, to.lat]);
    map.fitBounds(b, { padding: 140, duration: 900, maxZoom: 9 });

    const t0 = performance.now();
    const span = DUR.transit - 900;
    const tick = (now: number) => {
      const p = Math.max(0, Math.min(1, (now - t0 - 700) / span));
      // 缓入缓出，匀速看着像机器在拖
      const e = p < 0.5 ? 2 * p * p : 1 - ((-2 * p + 2) ** 2) / 2;
      markerRef.current?.setLngLat([
        from.lon + (to.lon - from.lon) * e,
        from.lat + (to.lat - from.lat) * e,
      ]);
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
      {/* 竖图不裁: 背后放一张放大模糊的同一张图当底，比黑边体面得多 */}
      <div
        className="absolute inset-0 scale-110 bg-cover bg-center blur-2xl
          opacity-45"
        style={{ backgroundImage: `url(${src})` }}
      />
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
