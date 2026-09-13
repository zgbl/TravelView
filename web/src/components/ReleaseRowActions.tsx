'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

/**
 * 安装包那一行的操作：下载 / 删除。
 *
 * **删除是真删**：数据库记录和磁盘上的包一起清掉（那个包就是几十 MB，
 * "删了但还占着磁盘"是最容易骗到自己的状态）。
 *
 * 删掉的如果正好是「当前版本」，服务端会把该平台剩下最新的一条顶上来。
 * 不这么做的话，那个平台会从下载页上凭空消失 —— 站长只会以为是下载页坏了，
 * 而真正的原因是他刚删了当前版本。
 */
export default function ReleaseRowActions({ r }: {
  r: {
    id: string; platform: string; version: string;
    isCurrent: boolean; externalUrl: string | null;
  };
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  async function remove() {
    const extra = r.isCurrent
      ? '\n\n它是这个平台的**当前版本** —— 删掉后下载页会给该平台剩下的最新版本；'
        + '如果那个平台没有别的版本了，下载页上就不会再有它。'
      : '';
    if (!confirm(`删掉 ${r.platform} ${r.version}？\n\n`
      + `安装包文件也会一起从服务器上删掉，不能撤销。${extra}`)) return;

    setBusy(true);
    setMsg(null);
    try {
      const res = await fetch(`/api/admin/releases?id=${r.id}`, { method: 'DELETE' });
      const j = await res.json().catch(() => ({}));
      if (!res.ok) {
        setMsg(j.error ?? `失败 (${res.status})`);
        return;
      }
      setMsg(j.promoted ? `已删除；当前版本切回 ${j.promoted}` : '已删除');
      router.refresh();
    } catch {
      setMsg('网络错误，没删成');
    } finally {
      setBusy(false);
    }
  }

  return (
    <td className="py-2 text-right">
      <div className="flex items-center justify-end gap-3">
        {msg && <span className="text-xs text-muted">{msg}</span>}
        <a href={r.externalUrl ?? `/api/releases/${r.id}/download`}
          target={r.externalUrl ? '_blank' : undefined}
          rel="noreferrer"
          className="text-xs text-muted hover:text-paper">下载</a>
        <button onClick={remove} disabled={busy}
          className="rounded-lg border border-red-400/30 px-2.5 py-1 text-xs
            text-red-300 transition hover:bg-red-400/10 disabled:opacity-30">
          {busy ? '删除中…' : '删除'}
        </button>
      </div>
    </td>
  );
}
