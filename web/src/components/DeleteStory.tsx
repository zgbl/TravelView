'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

/**
 * 删除一篇已发布的故事。
 *
 * **删除是不可撤销的，而且那个链接可能已经发给别人了**，
 * 所以确认框必须把"到底要删哪一篇"摆在眼前: 标题、日期、几站几张、
 * 完整网址、被看过多少次。浏览器原生的 confirm 做不到这些 ——
 * 它只能问"确定吗"，而用户在列表里点错一行是很常见的。
 */
export default function DeleteStory({
  id, title, subtitle, url, stats, views, compact = false,
}: {
  id: string;
  title: string;
  subtitle?: string | null;
  url: string;
  stats: string;
  views?: number;
  compact?: boolean;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function remove() {
    setBusy(true);
    setErr(null);
    const res = await fetch(`/api/stories/${id}`, { method: 'DELETE' });
    const j = await res.json().catch(() => ({}));
    if (!res.ok) {
      setErr(j.error ?? '删除失败');
      setBusy(false);
      return;
    }
    setOpen(false);
    setBusy(false);
    router.refresh();
  }

  return (
    <>
      <button
        onClick={(e) => { e.preventDefault(); e.stopPropagation(); setOpen(true); }}
        className={compact
          ? 'text-xs text-muted hover:text-red-400'
          : 'rounded-full border border-red-400/40 px-4 py-1.5 text-sm' +
            ' text-red-400 hover:bg-red-400/10'}
      >
        删除
      </button>

      {open && (
        <div
          className="fixed inset-0 z-[70] flex items-center justify-center
            bg-black/70 px-4"
          onClick={() => !busy && setOpen(false)}
        >
          <div
            className="w-full max-w-md rounded-2xl border border-white/12
              bg-[#16191c] p-6"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="text-lg font-semibold">删除这篇故事？</h2>

            {/* 把要删的东西完整摆出来，别让人凭记忆确认 */}
            <div className="mt-4 rounded-xl border border-white/10
              bg-black/25 p-4">
              <div className="font-medium">{title}</div>
              {subtitle && (
                <div className="mt-1 text-xs text-muted">{subtitle}</div>
              )}
              <div className="mt-2 text-xs text-muted">{stats}</div>
              <div className="mt-2 break-all text-xs text-muted">{url}</div>
              {views != null && views > 0 && (
                <div className="mt-2 text-xs text-amber-400">
                  这个链接已经被打开过 {views} 次，删掉之后别人再点就是 404。
                </div>
              )}
            </div>

            <ul className="mt-4 space-y-1 text-xs text-muted">
              <li>服务器上的照片会一并删除，无法恢复。</li>
              <li>你电脑上的原图不受影响。</li>
              <li>已经用掉的发布额度不会退回。</li>
            </ul>

            {err && <p className="mt-3 text-sm text-red-400">{err}</p>}

            <div className="mt-6 flex justify-end gap-3">
              <button
                onClick={() => setOpen(false)}
                disabled={busy}
                className="rounded-full border border-white/15 px-5 py-2
                  text-sm disabled:opacity-50"
              >
                取消
              </button>
              <button
                onClick={remove}
                disabled={busy}
                className="rounded-full bg-red-500 px-5 py-2 text-sm
                  font-medium text-white disabled:opacity-50"
              >
                {busy ? '正在删除...' : '确认删除'}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
