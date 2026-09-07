'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import DeleteStory from './DeleteStory';

export default function StoryActions({
  id, slug, visibility, title, stats, views,
}: {
  id: string; slug: string; visibility: string;
  title: string; stats: string; views: number;
}) {
  const router = useRouter();
  const [vis, setVis] = useState(visibility);
  const url = `${process.env.NEXT_PUBLIC_SITE_URL ?? ''}/s/${slug}`;

  async function setVisibility(v: string) {
    setVis(v);
    await fetch(`/api/stories/${id}`, {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ visibility: v }),
    });
    router.refresh();
  }

  return (
    <div className="mt-8 space-y-6">
      <div>
        <div className="mb-2 text-sm">可见性</div>
        <div className="flex gap-2">
          {[
            ['public', '公开'],
            ['unlisted', '仅链接可见'],
            ['private', '不可访问'],
          ].map(([v, label]) => (
            <button
              key={v}
              onClick={() => setVisibility(v)}
              className={`rounded-full border px-4 py-1.5 text-sm ${
                vis === v
                  ? 'border-accentBright bg-accentBright/15 text-accentBright'
                  : 'border-white/15 text-muted'
              }`}
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      <div className="flex flex-wrap gap-3">
        <a
          href={`https://www.facebook.com/sharer/sharer.php?u=${encodeURIComponent(url)}`}
          target="_blank" rel="noreferrer"
          className="rounded-xl border border-white/15 px-5 py-2.5 text-sm"
        >
          分享到 Facebook
        </a>
        <button
          onClick={() => navigator.clipboard.writeText(url)}
          className="rounded-xl border border-white/15 px-5 py-2.5 text-sm"
        >
          复制链接
        </button>
      </div>

      {/* 删除走带确认框的组件: 它会把标题、网址、浏览次数摆出来。
          **不能只弹一句"确定吗"** —— 删掉的是一个可能已经发给别人的链接 */}
      <DeleteStory
        id={id}
        title={title}
        url={url}
        stats={stats}
        views={views}
      />
    </div>
  );
}
