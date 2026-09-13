'use client';

import { useState } from 'react';
import { signIn } from 'next-auth/react';
import { useRouter } from 'next/navigation';
import { href, t, type Locale } from '@/lib/i18n';

/**
 * 用邮件里的一次性链接设置新密码。
 *
 * 成功之后**直接把人登录进去**，不要再把他丢回登录页重输一遍 ——
 * 他刚刚才证明了自己是邮箱的主人，也刚刚才亲手定下这个密码。
 */
export default function ResetForm(
  { token, locale }: { token: string; locale: Locale },
) {
  const router = useRouter();
  const [password, setPassword] = useState('');
  const [again, setAgain] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (password !== again) {
      setError(t(locale, 'reset.mismatch'));
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/auth/reset', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ token, password }),
      });
      const j = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(j.error ?? t(locale, res.status >= 500
          ? 'auth.err.server' : 'auth.err.network'));
        return;
      }
      // 密码是刚定的，这里一定能登进去；登不进去也不要卡住他，去登录页
      const r = await signIn('credentials', {
        email: j.email, password, redirect: false,
      });
      router.push(href(locale, r?.error ? '/login' : '/stories'));
      router.refresh();
    } catch {
      setError(t(locale, 'auth.err.network'));
    } finally {
      setBusy(false);
    }
  }

  const input = 'w-full rounded-xl border border-white/15 bg-white/5 px-4 py-3 '
    + 'outline-none focus:border-accentBright';

  return (
    <form onSubmit={submit} className="w-full max-w-sm space-y-4">
      <input
        type="password" required minLength={8} value={password} autoFocus
        autoComplete="new-password"
        placeholder={t(locale, 'auth.password.new')}
        onChange={(e) => setPassword(e.target.value)}
        className={input}
      />
      <input
        type="password" required minLength={8} value={again}
        autoComplete="new-password"
        placeholder={t(locale, 'reset.again')}
        onChange={(e) => setAgain(e.target.value)}
        className={input}
      />
      {error && <p className="text-sm text-red-400">{error}</p>}
      <button
        disabled={busy}
        className="w-full rounded-xl bg-accentBright py-3 font-medium text-ink
          disabled:opacity-50"
      >
        {busy ? t(locale, 'auth.busy') : t(locale, 'reset.submit')}
      </button>
    </form>
  );
}
