'use client';

import { useEffect, useRef, useState } from 'react';
import { mediaUrl, miles, thumbUrl, type Story } from '@/lib/story';
import StoryMap from './StoryMap';
import StoryOverviewMap from './StoryOverviewMap';
import PhotoLightbox from './PhotoLightbox';
import StoryPlayer from './StoryPlayer';
import StoryCover from './StoryCover';
import Logo from './Logo';
import { t, type Locale } from '@/lib/i18n';

/**
 * Story 渲染器 —— 网站上最重要的一个组件。
 *
 * 它同时是三样东西:
 *   1. 用户发布出去的成品页
 *   2. 落地页首屏的示例
 *   3. 将来视频和长图的取景来源
 * 所以它必须好看，而且必须只吃 Story manifest 这一种输入。
 */
export default function StoryRenderer({
  story,
  compact = false,
  locale = 'zh',
  prefix,
}: {
  story: Story;
  compact?: boolean;
  locale?: Locale;
  /** 图片在存储里的前缀（stories.media_prefix）。示例故事不传。 */
  prefix?: string | null;
}) {
  const [stopAt, setStopAt] = useState({ index: 0, frac: 0 });
  const [activeStop, setActiveStop] = useState<string | null>(null);
  const [activePhoto, setActivePhoto] = useState<string | null>(null);
  /// 大图看的是第几张（story.photos 里的下标）。null = 没打开
  const [lightbox, setLightbox] = useState<number | null>(null);
  /// 全屏播放。**滚动阅读仍然是默认**，这只是另一种看法
  const [playing, setPlaying] = useState(false);
  const indexOfPhoto = (id: string) => story.photos.findIndex((p) => p.id === id);
  const contentRef = useRef<HTMLDivElement>(null);

  /**
   * 小车的位置**按站算，不按滚动条算**。
   *
   * 原来是"页面滚了百分之几，小车就在总里程的百分之几"——
   * 这两件事没有任何关系: 一个二十几张照片的城市要滚很久却只走几英里，
   * 一段几百英里的高速可能一屏就过去了。结果就是你在读芝加哥，
   * 小车已经跑到密歇根湖南岸。
   *
   * 现在报给地图的是"第几站 + 这一站滚过了多少"，
   * 由地图把它换算成路线上的位置 —— 小车永远停在你正在看的那一站。
   */
  useEffect(() => {
    const onScroll = () => {
      const sections = Array.from(
        document.querySelectorAll<HTMLElement>('[data-stop]'));
      if (sections.length === 0) return;

      const mid = window.innerHeight / 2;
      let idx = 0;
      let frac = 0;
      for (let i = 0; i < sections.length; i++) {
        const r = sections[i].getBoundingClientRect();
        if (r.bottom < mid) { idx = i; frac = 1; continue; }
        if (r.top > mid) break;
        // 视口中线落在这一段里
        idx = i;
        frac = r.height > 0
          ? Math.max(0, Math.min(1, (mid - r.top) / r.height))
          : 0;
        break;
      }
      setStopAt({ index: idx, frac });
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
    return () => window.removeEventListener('scroll', onScroll);
  }, [story]);

  useEffect(() => {
    const obs = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) setActiveStop(e.target.getAttribute('data-stop'));
        }
      },
      { rootMargin: '-45% 0px -45% 0px' },
    );
    document.querySelectorAll('[data-stop]').forEach((el) => obs.observe(el));
    return () => obs.disconnect();
  }, [story]);

  const photoById = Object.fromEntries(story.photos.map((p) => [p.id, p]));
  const stopById = Object.fromEntries(story.stops.map((s) => [s.id, s]));
  const cover = story.cover ? photoById[story.cover] : undefined;
  // manifest 里没写就是地图 —— 老故事也一并换成地图片头，
  // 它们的封面本来就是"第一站的第一张"，没有任何人挑过
  /**
   * Story Cover 的形态。
   *
   * 'auto'（默认）= **由内容决定**: 有路线就用地图封面，没有就用照片封面。
   * 这个产品以后不只有旅行 —— 生日、婚礼、演唱会都没有路线，
   * 那时候封面引擎该自己退回照片，而不是画一张空地图。
   */
  const rawMode = (story as unknown as { coverMode?: string }).coverMode;
  const hasRoute = story.routes.length > 0 || story.stops.length > 1;
  const coverMode: 'map' | 'mapcard' | 'photo' =
    rawMode === 'photo' ? 'photo'
      : !hasRoute ? 'photo'                      // 没有路线一律照片封面
      : rawMode === 'mapcard' ? 'mapcard'
      : 'map';                                   // auto / map 都是整屏地图
  /// 封面已经是地图了，下面就不该再来一张大地图 ——
  /// 同一页两张大地图，第二张只会把第一张的分量稀释掉
  const showOverviewMap = coverMode === 'photo';

  return (
    <div className="bg-ink text-paper">
      {/* Hero */}
      {coverMode === 'mapcard' ? (
        /* 方案 B: 标题在地图外面，地图做成一张干净的卡片。
           最保守 —— 地图一个像素都没被遮住。 */
        <section className="px-[6vw] pb-[6vh] pt-[9vh]">
          <h1 className="text-[clamp(34px,6vw,68px)] font-semibold
            leading-[1.08] tracking-tight">
            {story.title}
          </h1>
          {story.subtitle && (
            <p className="mt-3 text-[clamp(14px,2vw,19px)] text-muted">
              {story.subtitle}
            </p>
          )}
          <div className="mt-7 flex flex-wrap items-center gap-5">
            <div className="flex flex-wrap gap-8">
              <Stat n={story.stats.days} k="DAYS" />
              <Stat n={story.stats.stops} k="STOPS" />
              <Stat n={miles(story.stats.distanceMeters)} k="MILES" />
              <Stat n={story.stats.photos} k="PHOTOS" />
            </div>
            <PlayButton onClick={() => setPlaying(true)} locale={locale} />
          </div>
          <div className="relative mt-8 h-[62vh] overflow-hidden rounded-3xl">
            {!playing && <StoryCover story={story} bottomPad={70} />}
            {/* 只在四周收一圈内阴影，中间完全干净 */}
            <div className="pointer-events-none absolute inset-0 rounded-3xl
              shadow-[inset_0_0_90px_rgba(15,17,19,.55)]" />
          </div>
        </section>
      ) : (
        <section className="relative flex h-[88vh] items-end overflow-hidden">
          {/* 方案 A: 整屏真地图。**底图一点都不压暗** ——
              只有画面下方约一半有一层从透明渐变到深色的遮罩托住标题，
              上半张地图完全没被遮。路线本身是"深描边 + 亮线"两层，
              所以在任何底图上都跳得出来。 */}
          {coverMode === 'map' ? (
            <div className="absolute inset-0">
              {!playing && <StoryCover story={story} />}
              <div className="pointer-events-none absolute inset-x-0 bottom-0
                h-[58%] bg-gradient-to-t from-ink via-ink/75 to-transparent" />
            </div>
          ) : cover ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={mediaUrl(cover.web.path, prefix)}
              alt=""
              className="absolute inset-0 h-full w-full object-cover
                brightness-[.6]"
            />
          ) : null}
          <div className="relative max-w-3xl px-[6vw] pb-[8vh]"
            style={{ textShadow: '0 2px 18px rgba(0,0,0,.55)' }}>
            <h1 className="text-[clamp(34px,6vw,68px)] font-semibold
              leading-[1.08] tracking-tight">
              {story.title}
            </h1>
            {story.subtitle && (
              <p className="mt-3 text-[clamp(14px,2vw,19px)] text-white/90">
                {story.subtitle}
              </p>
            )}
            <div className="mt-7 flex flex-wrap items-center gap-5">
              <div className="inline-flex flex-wrap gap-8 rounded-2xl
                bg-black/25 px-6 py-4 backdrop-blur-sm">
                <Stat n={story.stats.days} k="DAYS" />
                <Stat n={story.stats.stops} k="STOPS" />
                <Stat n={miles(story.stats.distanceMeters)} k="MILES" />
                <Stat n={story.stats.photos} k="PHOTOS" />
              </div>
              <PlayButton onClick={() => setPlaying(true)} locale={locale} />
            </div>
          </div>
        </section>
      )}

      {/* ② 行程全览。**封面已经是地图时不显示** ——
          同一页两张大地图，第二张会把封面的分量整个稀释掉。
          读者要动手看地图，右侧那张跟着阅读走的就是。 */}
      {showOverviewMap && (
        <section className="px-[6vw] pb-[4vh] pt-[8vh]">
          <h2 className="text-[clamp(22px,3vw,32px)] font-semibold tracking-tight">
            {t(locale, 'story.overview')}
          </h2>
          <p className="mb-6 text-sm text-muted">
            {t(locale, 'story.overview.sub', {
              stops: story.stats.stops,
              miles: miles(story.stats.distanceMeters),
            })}
          </p>
          {!playing && <StoryOverviewMap story={story} />}
        </section>
      )}

      {/* 正文 + 固定地图 */}
      <div className="grid lg:grid-cols-[minmax(0,1fr)_46vw]">
        <div ref={contentRef} className="max-w-[760px] px-[5vw] py-[6vh]">
          {story.days.map((day, di) => (
            <section key={day.date} className="mb-[10vh]">
              <h2 className="mb-2 text-xs uppercase tracking-[0.16em] text-muted">
                Day {di + 1} &middot; {day.date}
              </h2>
              {day.stops.map((sid) => {
                const s = stopById[sid];
                if (!s) return null;
                const hero = s.hero ? photoById[s.hero] : undefined;
                const rest = s.photos.filter((p) => p !== s.hero);
                return (
                  <article
                    key={s.id}
                    data-stop={s.id}
                    className="mb-[7vh] scroll-mt-[20vh]"
                  >
                    <h3 className="text-[clamp(22px,3vw,32px)] font-semibold tracking-tight">
                      {/* 英文页看英文。没有译文才回落到原文 ——
                          宁可显示中文，也不能显示空白 */}
                      {(locale === 'en' ? s.nameEn ?? s.name : s.name) ??
                        `第 ${s.seq + 1} 站`}
                    </h3>
                    <p className="mb-3 text-sm text-muted">
                      {hhmm(s.arrive)} - {hhmm(s.leave)} &middot;{' '}
                      {t(locale, 'story.selected', { n: s.photos.length })}
                    </p>
                    {(locale === 'en' ? s.noteEn ?? s.note : s.note) && (
                      <p className="mb-4 max-w-[62ch] whitespace-pre-line
                        text-[15px] leading-relaxed text-paper/85">
                        {locale === 'en' ? s.noteEn ?? s.note : s.note}
                      </p>
                    )}
                    {hero && (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={mediaUrl(hero.web.path, prefix)}
                        alt=""
                        loading="lazy"
                        onMouseEnter={() => setActivePhoto(hero.id)}
                        onClick={() => setLightbox(indexOfPhoto(hero.id))}
                        className={`w-full cursor-zoom-in rounded-2xl
                          outline-accent transition-[outline-width] ${
                            activePhoto === hero.id
                              ? 'outline outline-[3px]'
                              : 'outline-0'
                          }`}
                      />
                    )}
                    {rest.length > 0 && (
                      <div className="mt-3 grid grid-cols-[repeat(auto-fill,minmax(170px,1fr))] gap-2.5">
                        {rest.map((pid) => {
                          const ph = photoById[pid];
                          if (!ph) return null;
                          return (
                            // eslint-disable-next-line @next/next/no-img-element
                            <img
                              key={pid}
                              src={thumbUrl(ph, prefix)}
                              alt=""
                              loading="lazy"
                              onMouseEnter={() => setActivePhoto(ph.id)}
                              onClick={() => setLightbox(indexOfPhoto(ph.id))}
                              className={`w-full cursor-zoom-in rounded-xl
                                object-cover outline-accent
                                transition-[outline-width] ${
                                ph.web.h > ph.web.w
                                  ? 'aspect-[3/4]'
                                  : 'aspect-square'
                              } ${
                                activePhoto === ph.id
                                  ? 'outline outline-[3px]'
                                  : 'outline-0'
                              }`}
                            />
                          );
                        })}
                      </div>
                    )}
                  </article>
                );
              })}
            </section>
          ))}
        </div>

        {/* 播放时把这张地图**卸载掉**，不是藏起来。
            display:none 不会释放 WebGL 上下文和它的显存 ——
            播放器自己还要开一张地图，页面上同时活着三张，
            在 5K 屏最大化时 Chrome 会直接杀掉这个标签页。 */}
        <div className="sticky top-0 hidden h-screen lg:block">
          {!playing && <StoryMap
            story={story}
            stopAt={stopAt}
            activeStop={activeStop}
            activePhoto={activePhoto}
          />}
        </div>
      </div>

      {playing && (
        <StoryPlayer
          story={story}
          prefix={prefix}
          locale={locale}
          onClose={() => setPlaying(false)}
        />
      )}

      {lightbox !== null && (
        <PhotoLightbox
          photos={story.photos}
          index={lightbox}
          prefix={prefix}
          onClose={() => setLightbox(null)}
          onIndex={(i) => {
            setLightbox(i);
            // 大图翻页时地图上的定位点跟着走 —— 大图里最想知道的
            // 就是"这张在哪拍的"
            const ph = story.photos[i];
            if (ph) setActivePhoto(ph.id);
          }}
        />
      )}

      {/* 结束卡片 —— 专门为被截图分享而设计 */}
      {!compact && (
        <section className="bg-[#191c1f] px-[6vw] py-[14vh] text-center">
          <div className="inline-block rounded-3xl border border-white/10 bg-gradient-to-br from-[#1d2226] to-[#12161a] px-14 py-12">
            <h2 className="text-[clamp(26px,4vw,40px)] font-semibold">
              {story.title}
            </h2>
            <p className="mb-8 text-muted">
              {dateOnly(story.start)} - {dateOnly(story.end)}
            </p>
            <div className="flex flex-wrap justify-center gap-10">
              <Big n={story.stats.days} k="天" />
              <Big n={story.stats.stops} k="站" />
              <Big n={miles(story.stats.distanceMeters)} k="英里" />
              <Big n={story.stats.photos} k="张照片" />
            </div>
          </div>
          {/* 作品页顶上不挂导航，所以回家的那条路在这里。
              每一篇被分享出去的 Story 都是一个入口 —— 这一行是增长回路 */}
          <a href="/" className="mt-10 inline-flex items-center gap-2
            text-sm text-muted transition-colors hover:text-paper">
            <Logo size={20} />
            {t(locale, 'story.madewith')}
          </a>
          <p className="mt-6 text-xs text-muted">
            路线根据照片位置推算 &middot; 地图数据 &copy; OpenStreetMap 贡献者
          </p>
        </section>
      )}
    </div>
  );
}

/**
 * 全屏播放的入口。
 *
 * **放在封面上、紧挨着那四个数字** —— 读者刚看到"5 天 72 站 1949 英里"
 * 的那一刻，正是最想知道"这一路都有什么"的时候。
 * 藏在页脚或菜单里，等于没有。
 */
function PlayButton({
  onClick, locale,
}: { onClick: () => void; locale: Locale }) {
  return (
    <button
      onClick={onClick}
      className="group flex items-center gap-3 rounded-full bg-white/95
        px-6 py-3.5 text-ink transition hover:bg-white"
    >
      <span className="flex h-7 w-7 items-center justify-center rounded-full
        bg-ink text-[11px] text-paper">▶</span>
      <span className="text-left">
        <span className="block text-sm font-semibold">
          {t(locale, 'player.open')}
        </span>
        <span className="block text-[11px] text-ink/55">
          {t(locale, 'player.hint')}
        </span>
      </span>
    </button>
  );
}

function Stat({ n, k }: { n: number; k: string }) {
  return (
    <div>
      <div className="text-2xl font-semibold">{n}</div>
      <div className="text-[11px] tracking-[0.08em] text-white/70">{k}</div>
    </div>
  );
}

function Big({ n, k }: { n: number; k: string }) {
  return (
    <div>
      <div className="text-4xl font-semibold leading-none">{n}</div>
      <div className="mt-1.5 text-xs tracking-[0.1em] text-muted">{k}</div>
    </div>
  );
}

function hhmm(iso: string) {
  return new Date(iso).toTimeString().slice(0, 5);
}
function dateOnly(iso: string) {
  return new Date(iso).toLocaleDateString('zh-CN', {
    month: 'long',
    day: 'numeric',
  });
}
