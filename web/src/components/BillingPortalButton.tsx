'use client';

import { useState } from 'react';

/** 打开 Stripe 客户门户: 换卡、看发票、取消订阅，全部不用找我们人工 */
export default function BillingPortalButton({ label }: { label: string }) {
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);

  async function go() {
    setBusy(true);
    setNote(null);
    const res = await fetch('/api/billing', { method: 'POST' });
    const j = await res.json().catch(() => ({}));
    if (j.url) {
      window.location.href = j.url;
      return;
    }
    setNote(j.message ?? j.error ?? '暂时打不开，请稍后再试');
    setBusy(false);
  }

  return (
    <div>
      <button
        onClick={go}
        disabled={busy}
        className="rounded-full border border-white/20 px-5 py-2 text-sm
          font-medium hover:border-white/40 disabled:opacity-50"
      >
        {busy ? '正在打开...' : label}
      </button>
      {note && <p className="mt-2 text-xs text-muted">{note}</p>}
    </div>
  );
}
