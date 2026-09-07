'use client';

import { useEffect, useState } from 'react';
import { mediaUrl, type StoryPhoto } from '@/lib/story';

/**
 * 点开看大图。
 *
 * 缩略图能看清"有这么一张"，看不清"这张拍到了什么"。
 * 一篇游记里读者最想做的第二件事（第一件是滚下去）就是点开某一张。
 *
 * 交互刻意做到最少:
 *   桌面 —— 点图打开，← → 翻页，Esc 或点背景关掉
 *   手机 —— 点图打开，左右滑翻页，再点一下关掉
 *
 * 用的是 photos/ 里那张 1600px 的派生图，不额外加载任何东西 ——
 * 大图和页面里的图是同一个文件，点开是瞬时的。
 */
export default function PhotoLightbox({
  photos,
  index,
  prefix,
  onClose,
  onIndex,
}: {
  photos: StoryPhoto[];
  index: number;
  prefix?: string | null;
  onClose: () => void;
  onIndex: (i: number) => void;
}) {
  const [touchX, setTouchX] = useState<number | null>(null);
  const photo = photos[index];

  const go = (d: number) => {
    const n = photos.length;
    if (n > 0) onIndex(((index + d) % n + n) % n);
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
      if (e.key === 'ArrowRight') go(1);
      if (e.key === 'ArrowLeft') go(-1);
    };
    window.addEventListener('keydown', onKey);
    // 打开时锁住背景滚动，否则手指一滑整篇故事就跑了
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = prev;
    };
  });

  if (!photo) return null;

  return (
    <div
      className="fixed inset-0 z-[60] flex items-center justify-center
        bg-black/92 backdrop-blur-sm"
      onClick={onClose}
      onTouchStart={(e) => setTouchX(e.touches[0]?.clientX ?? null)}
      onTouchEnd={(e) => {
        if (touchX == null) return;
        const dx = (e.changedTouches[0]?.clientX ?? touchX) - touchX;
        // 滑动超过 50px 算翻页，否则当成"再点一下"关掉
        if (Math.abs(dx) > 50) go(dx < 0 ? 1 : -1);
        setTouchX(null);
      }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={mediaUrl(photo.web.path, prefix)}
        alt=""
        className="max-h-[92vh] max-w-[94vw] object-contain"
      />

      {photo.caption && (
        <p className="pointer-events-none absolute inset-x-0 bottom-6
          px-6 text-center text-sm text-white/80">
          {photo.caption}
        </p>
      )}

      <button
        onClick={(e) => { e.stopPropagation(); onClose(); }}
        aria-label="关闭"
        className="absolute right-4 top-4 h-10 w-10 rounded-full
          bg-white/10 text-xl text-white/80 hover:bg-white/20"
      >
        ×
      </button>

      {photos.length > 1 && (
        <>
          <button
            onClick={(e) => { e.stopPropagation(); go(-1); }}
            aria-label="上一张"
            className="absolute left-3 hidden h-12 w-12 rounded-full
              bg-white/10 text-2xl text-white/80 hover:bg-white/20 sm:block"
          >
            ‹
          </button>
          <button
            onClick={(e) => { e.stopPropagation(); go(1); }}
            aria-label="下一张"
            className="absolute right-3 hidden h-12 w-12 rounded-full
              bg-white/10 text-2xl text-white/80 hover:bg-white/20 sm:block"
          >
            ›
          </button>
          <div className="pointer-events-none absolute left-1/2 top-5
            -translate-x-1/2 text-xs text-white/50">
            {index + 1} / {photos.length}
          </div>
        </>
      )}
    </div>
  );
}
