'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export type PlanButton = {
  key: string;
  name: string;
  priceLabel: string;
  blurb: string;
  available: boolean;
  primary?: boolean;
};

/**
 * 档位不写死在这里 —— 由服务端从 PLANS 传进来，
 * 否则加一档价格要改两个文件，迟早对不上。
 */
export default function CheckoutButtons({ plans }: { plans: PlanButton[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);

  async function go(plan: string) {
    setBusy(plan);
    setNote(null);
    const res = await fetch('/api/checkout', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ plan }),
    });
    if (res.status === 401) {
      router.push('/login?next=/pricing');
      return;
    }
    const j = await res.json().catch(() => ({}));
    if (j.url) {
      window.location.href = j.url;
      return;
    }
    // 支付没开通时说人话，别把用户扔在一个点了没反应的按钮前
    setNote(j.message ?? j.error ?? '暂时无法发起支付，请稍后再试');
    setBusy(null);
  }

  return (
    <div className="mt-8">
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {plans.filter((p) => p.available).map((p) => (
          <button
            key={p.key}
            onClick={() => go(p.key)}
            disabled={busy !== null}
            className={`rounded-xl px-4 py-3 text-left font-medium
              disabled:opacity-50 ${p.primary
                ? 'bg-accentBright text-ink'
                : 'border border-white/15'}`}
          >
            <span className="block text-sm">
              {busy === p.key ? '正在跳转...' : p.name}
            </span>
            <span className={`block text-xs ${p.primary
              ? 'text-ink/70' : 'text-muted'}`}>
              {p.priceLabel} · {p.blurb}
            </span>
          </button>
        ))}
      </div>
      {note && <p className="mt-4 text-center text-sm text-muted">{note}</p>}
    </div>
  );
}
