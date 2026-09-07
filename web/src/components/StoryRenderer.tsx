'use client';

import { useEffect, useRef, useState } from 'react';
import { mediaUrl, miles, type Story } from '@/lib/story';
import StoryMap from './StoryMap';
import StoryOverviewMap from './StoryOverviewMap';
import PhotoLightbox from './PhotoLightbox';
import RouteArtwork from './RouteArtwork';
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
  const coverMode =
    (story as unknown as { coverMode?: string }).coverMode === 'photo'
      ? 'photo' : 'map';

  return (
    <div className="bg-ink text-paper">
      {/* Hero */}
      <section className="relative flex h-[88vh] items-end overflow-hidden">
        {/* 片头用路线图还是照片。默认路线图 ——
            一张照片谁都有，这条真实走过的路线只有这一趟有，
            它才是这篇东西第一眼该给人看的东西。 */}
        {coverMode === 'map' ? (
          <div className="absolute inset-0">
            <RouteArtwork story={story} />
            {/* 底部压暗，保证标题永远读得清 */}
            <div className="absolute inset-0 bg-gradient-to-t
              from-ink via-ink/45 to-ink/10" />
          </div>
        ) : cover ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={mediaUrl(cover.web.path, prefix)}
            alt=""
            className="absolute inset-0 h-full w-full object-cover brightness-[.6]"
          />
        ) : null}
        <div className="relative max-w-3xl px-[6vw] pb-[8vh]">
          <h1 className="text-[clamp(34px,6vw,68px)] font-semibold leading-[1.08] tracking-tight">
            {story.title}
          </h1>
          {story.subtitle && (
            <p className="mt-3 text-[clamp(14px,2vw,19px)] text-white/85">
              {story.subtitle}
            </p>
          )}
          <div className="mt-7 flex flex-wrap gap-8">
            <Stat n={story.stats.days} k="DAYS" />
            <Stat n={story.stats.stops} k="STOPS" />
            <Stat n={miles(story.stats.distanceMeters)} k="MILES" />
            <Stat n={story.stats.photos} k="PHOTOS" />
          </div>
        </div>
      </section>

      {/* ② Route: 整趟旅行的全貌，分享出去第一眼想看的就是它 */}
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
        <StoryOverviewMap story={story} />
      </section>

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
                      {s.name ?? `第 ${s.seq + 1} 站`}
                    </h3>
                    <p className="mb-3 text-sm text-muted">
                      {hhmm(s.arrive)} - {hhmm(s.leave)} &middot;{' '}
                      {t(locale, 'story.selected', { n: s.photos.length })}
                    </p>
                    {s.note && (
                      <p className="mb-4 max-w-[62ch] whitespace-pre-line
                        text-[15px] leading-relaxed text-paper/85">
                        {s.note}
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
                              src={mediaUrl(ph.web.path, prefix)}
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

        <div className="sticky top-0 hidden h-screen lg:block">
          <StoryMap
            story={story}
            stopAt={stopAt}
            activeStop={activeStop}
            activePhoto={activePhoto}
          />
        </div>
      </div>

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
          <p className="mt-10 text-xs text-muted">
            路线根据照片位置推算 &middot; 地图数据 &copy; OpenStreetMap 贡献者
          </p>
        </section>
      )}
    </div>
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
