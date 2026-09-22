'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import PayQr, { type QrLabels } from './PayQr';

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
 *
 * 两条付款路径:
 *   - 点档位本身: 跳去 Stripe 收银台（电脑上直接付）
 *   - 点"扫码支付": 同样建一个会话，但把会话地址画成二维码，
 *     用手机扫着付 —— 手机上 Apple Pay / 微信支付比在电脑上敲卡号顺
 *
 * 两条路建的是**同一个接口的同一个会话**，都带 `metadata.userId`，
 * 所以权益发放走的是同一条 webhook。二维码里绝不能换成 Stripe 后台
 * 那个 Payment Link: 它是静态的，认不出扫码的是谁。
 */
export default function CheckoutButtons({
  plans, busyLabel, errLabel, loginPath, qrLabels,
}: {
  plans: PlanButton[];
  busyLabel: string;
  errLabel: string;
  loginPath: string;
  qrLabels: QrLabels & { action: string };
}) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [qr, setQr] = useState<{ url: string; name: string } | null>(null);

  /** 建会话。扫码和直接跳转共用，免得两条路的参数长歪。 */
  async function createSession(plan: string): Promise<string | null> {
    const res = await fetch('/api/checkout', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ plan }),
    });
    if (res.status === 401) {
      router.push(`${loginPath}?next=/account/billing`);
      return null;
    }
    const j = await res.json().catch(() => ({}));
    if (j.url) return j.url as string;
    // 支付没开通时说人话，别把用户扔在一个点了没反应的按钮前
    setNote(j.message ?? j.error ?? errLabel);
    return null;
  }

  async function go(plan: string) {
    setBusy(plan);
    setNote(null);
    const url = await createSession(plan);
    if (url) {
      window.location.href = url;
      return;
    }
    setBusy(null);
  }

  async function goQr(plan: string, name: string) {
    setBusy(plan);
    setNote(null);
    const url = await createSession(plan);
    setBusy(null);
    if (url) setQr({ url, name });
  }

  return (
    <div className="mt-8">
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {plans.filter((p) => p.available).map((p) => (
          <div key={p.key} className="flex flex-col gap-1.5">
            <button
              onClick={() => go(p.key)}
              disabled={busy !== null}
              className={`rounded-xl px-4 py-3 text-left font-medium
                disabled:opacity-50 ${p.primary
                  ? 'bg-accentBright text-ink'
                  : 'border border-white/15'}`}
            >
              <span className="block text-sm">
                {busy === p.key ? busyLabel : p.name}
              </span>
              <span className={`block text-xs ${p.primary
                ? 'text-ink/70' : 'text-muted'}`}>
                {p.priceLabel} · {p.blurb}
              </span>
            </button>
            <button
              onClick={() => goQr(p.key, `${p.name} · ${p.priceLabel}`)}
              disabled={busy !== null}
              className="rounded-lg px-1 py-1 text-xs text-muted
                underline underline-offset-2 transition-colors
                hover:text-paper disabled:opacity-50"
            >
              {qrLabels.action}
            </button>
          </div>
        ))}
      </div>
      {note && <p className="mt-4 text-center text-sm text-muted">{note}</p>}

      {qr && (
        <PayQr
          url={qr.url}
          planName={qr.name}
          labels={qrLabels}
          // 付款在手机上完成，这一页得手动重取一次才知道额度变了。
          // webhook 才是发权益的那一方，刷新只是把结果读回来。
          onDone={() => { setQr(null); router.refresh(); }}
          onClose={() => setQr(null)}
        />
      )}
    </div>
  );
}
