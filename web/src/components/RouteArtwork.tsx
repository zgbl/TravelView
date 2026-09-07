'use client';

import { useEffect, useRef, useState } from 'react';
import { routeArt } from '@/lib/route-art';
import type { Story } from '@/lib/story';

/**
 * 片头用的路线图。
 *
 * 刻意**不是一张地图**: 没有瓦片、没有地名、没有交互。
 * 片头要的是一个形状 —— 一眼认出"这趟走了这么远、这么绕"，
 * 至于哪条街哪个城市，下面那张真地图会回答。
 * 顺带的好处是它不依赖瓦片服务，首屏永远秒开，也不泄露访客行踪。
 */
export default function RouteArtwork({ story }: { story: Story }) {
  const ref = useRef<HTMLDivElement>(null);
  const [box, setBox] = useState({ w: 1200, h: 700 });

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const ro = new ResizeObserver(() => {
      setBox({ w: el.clientWidth || 1200, h: el.clientHeight || 700 });
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const art = routeArt(story, box.w, box.h, Math.min(box.w, box.h) * 0.12);

  return (
    <div ref={ref} className="h-full w-full bg-ink">
      {art && (
        <svg
          width={box.w}
          height={box.h}
          viewBox={`0 0 ${box.w} ${box.h}`}
          className="h-full w-full"
        >
          {/* 两条线叠出发光感: 底下一条粗的暗线，上面一条细的亮线 */}
          <path d={art.path} fill="none" stroke="#1f6f63"
            strokeWidth={16} strokeLinecap="round" strokeLinejoin="round"
            opacity={0.45} />
          <path
            d={art.path}
            fill="none"
            stroke="#4fbfa8"
            strokeWidth={5}
            strokeLinecap="round"
            strokeLinejoin="round"
            className="[stroke-dasharray:1] [stroke-dashoffset:0]"
            style={{
              strokeDasharray: 4000,
              strokeDashoffset: 4000,
              animation: 'tvDraw 2.6s ease-out forwards',
            }}
          />
          {art.stops.map((p, i) => (
            <circle key={i} cx={p.x} cy={p.y} r={5}
              fill="#0f1113" stroke="#4fbfa8" strokeWidth={3} />
          ))}
          {art.end && (
            <circle cx={art.end.x} cy={art.end.y} r={9}
              fill="#ff8a5b" stroke="#0f1113" strokeWidth={3} />
          )}
          <style>{`@keyframes tvDraw { to { stroke-dashoffset: 0 } }`}</style>
        </svg>
      )}
    </div>
  );
}
