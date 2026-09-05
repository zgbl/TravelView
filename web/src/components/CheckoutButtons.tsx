'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export default function CheckoutButtons() {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);

  async function go(plan: 'onetime' | 'subscription') {
    setBusy(plan);
    const res = await fetch('/api/checkout', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ plan }),
    });
    if (res.status === 401) {
      router.push('/login?next=/pricing');
      return;
    }
    const j = await res.json();
    if (j.url) window.location.href = j.url;
    else setBusy(null);
  }

  return (
    <div className="mt-8 grid gap-6 md:grid-cols-2">
      <button
        onClick={() => go('onetime')}
        disabled={busy !== null}
        className="rounded-xl border border-white/15 py-3 font-medium
          disabled:opacity-50"
      >
        {busy === 'onetime' ? '正在跳转...' : '购买单篇发布'}
      </button>
      <button
        onClick={() => go('subscription')}
        disabled={busy !== null}
        className="rounded-xl bg-accentBright py-3 font-medium text-ink
          disabled:opacity-50"
      >
        {busy === 'subscription' ? '正在跳转...' : '订阅一年'}
      </button>
    </div>
  );
}
