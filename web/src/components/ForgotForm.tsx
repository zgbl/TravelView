'use client';

import { useState } from 'react';
import { t, type Locale } from '@/lib/i18n';

/**
 * 申请一封重置密码的信。
 *
 * **成功后不再显示表单**，只留一句"信发出去了，去邮箱点那个链接"。
 * 让输入框继续留在那儿，用户会以为没成功，然后连点五次 ——
 * 收件箱里五封信，只有最后一封是活的，那才是真的困惑。
 */
export default function ForgotForm({ locale }: { locale: Locale }) {
  const [email, setEmail] = useState('');
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/auth/forgot', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ email, locale }),
      });
      if (!res.ok) {
        const j = await res.json().catch(() => ({}));
        setError(j.error ?? t(locale, res.status >= 500
          ? 'auth.err.server' : 'auth.err.network'));
        return;
      }
      setSent(true);
    } catch {
      setError(t(locale, 'auth.err.network'));
    } finally {
      setBusy(false);
    }
  }

  if (sent) {
    return (
      <div className="w-full max-w-sm rounded-2xl border border-white/12
        bg-white/[.04] p-5">
        <p className="text-sm leading-relaxed">{t(locale, 'forgot.sent')}</p>
        <p className="mt-3 text-xs leading-relaxed text-muted">
          {t(locale, 'forgot.sent.hint')}
        </p>
      </div>
    );
  }

  return (
    <form onSubmit={submit} className="w-full max-w-sm space-y-4">
      <input
        type="email" required value={email} autoFocus autoComplete="email"
        placeholder={t(locale, 'auth.email')}
        onChange={(e) => setEmail(e.target.value)}
        className="w-full rounded-xl border border-white/15 bg-white/5 px-4 py-3
          outline-none focus:border-accentBright"
      />
      {error && <p className="text-sm text-red-400">{error}</p>}
      <button
        disabled={busy}
        className="w-full rounded-xl bg-accentBright py-3 font-medium text-ink
          disabled:opacity-50"
      >
        {busy ? t(locale, 'auth.busy') : t(locale, 'forgot.submit')}
      </button>
    </form>
  );
}
