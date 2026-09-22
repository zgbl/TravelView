'use client';

import { useEffect, useState } from 'react';

export type QrLabels = {
  title: string;
  hint: string;
  done: string;
  failed: string;
  close: string;
};

/**
 * 扫码支付的二维码。
 *
 * ⚠ 编码的必须是**这一个用户自己的 Checkout 会话地址**，不能是 Stripe
 * 后台那个 Payment Link。Payment Link 是静态的: 它对所有人都是同一个值，
 * 带不出 `metadata.userId`，于是 webhook 里
 * `const userId = s.metadata?.userId; if (userId) {...}` 取不到人 ——
 * 用户钱付了、额度一条不发。会话地址是每次点购买现建的，认得出是谁。
 */
export default function PayQr({
  url, planName, labels, onDone, onClose,
}: {
  url: string;
  planName: string;
  labels: QrLabels;
  onDone: () => void;
  onClose: () => void;
}) {
  const [qr, setQr] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let alive = true;
    // 按需加载: 不为一个不一定会点的按钮拖慢首屏（和 ShareBar 同一个理由）
    import('qrcode')
      .then((m) => m.toDataURL(url, { width: 480, margin: 1 }))
      .then((d) => { if (alive) setQr(d); })
      .catch(() => { if (alive) setFailed(true); });
    return () => { alive = false; };
  }, [url]);

  // Esc 关掉。模态框不给人逃生的键盘路径是很烦的
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div
      role="dialog"
      aria-modal="true"
      onClick={onClose}
      className="fixed inset-0 z-50 flex items-center justify-center
        bg-ink/80 px-6 backdrop-blur-sm"
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-sm rounded-2xl border border-white/12
          bg-ink p-6 text-center"
      >
        <h2 className="text-base font-semibold">{labels.title}</h2>
        <p className="mt-1 text-xs text-muted">{planName}</p>

        {/* 二维码底下**必须是白的** —— 深色底大多数相机扫不出来 */}
        <div className="mx-auto mt-5 flex h-56 w-56 items-center
          justify-center rounded-xl bg-white p-3">
          {qr ? (
            <img src={qr} alt="" width={224} height={224}
              className="h-full w-full" />
          ) : (
            <span className="px-2 text-xs leading-relaxed text-ink/60">
              {failed ? labels.failed : '· · ·'}
            </span>
          )}
        </div>

        <p className="mt-4 text-xs leading-relaxed text-muted">{labels.hint}</p>

        {/* 付款是在手机上完成的，这一页不会自己变 —— 得让人知道按哪个按钮 */}
        <button
          onClick={onDone}
          className="mt-5 w-full rounded-xl bg-accentBright px-4 py-3
            font-medium text-ink"
        >
          {labels.done}
        </button>
        <button
          onClick={onClose}
          className="mt-2 w-full rounded-xl border border-white/15
            px-4 py-3 text-sm text-paper"
        >
          {labels.close}
        </button>
      </div>
    </div>
  );
}
