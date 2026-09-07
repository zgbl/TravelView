'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export default function StoryActions({
  id, slug, visibility,
}: { id: string; slug: string; visibility: string }) {
  const router = useRouter();
  const [vis, setVis] = useState(visibility);
  const [busy, setBusy] = useState(false);
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

  async function remove() {
    if (!confirm('删除这篇故事？服务器上的图片也会一并删除，无法恢复。\n' +
      '你电脑上的原图不受影响。\n\n' +
      '如果这是重复发布的一篇（还有另一篇日期重叠的在线上），' +
      '当时扣的额度会退回来。')) return;
    setBusy(true);
    const res = await fetch(`/api/stories/${id}`, { method: 'DELETE' });
    const j = await res.json().catch(() => ({}));
    // 退了额度就明说 —— 用户删掉重复的那篇时最想确认的就是这件事
    if (j.refunded) alert('已删除，重复发布扣掉的 1 篇额度已经退回你的账户。');
    router.push('/stories');
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

      <button
        onClick={remove}
        disabled={busy}
        className="text-sm text-red-400 hover:underline disabled:opacity-50"
      >
        删除这篇故事
      </button>
    </div>
  );
}
