'use client';

import { useState } from 'react';
import { signIn } from 'next-auth/react';
import { useRouter } from 'next/navigation';
import { href, t, type Locale } from '@/lib/i18n';

export default function AuthForm(
  { mode, locale = 'zh' }: { mode: 'login' | 'signup'; locale?: Locale },
) {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      if (mode === 'signup') {
        const res = await fetch('/api/signup', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ email, password }),
        });
        if (!res.ok) {
            setError((await res.json()).error ?? t(locale, 'auth.err.network'));
          return;
        }
      }
      const r = await signIn('credentials', {
        email, password, redirect: false,
      });
      if (r?.error) {
        setError(t(locale, mode === 'signup'
          ? 'auth.err.signedup' : 'auth.err.credentials'));
        return;
      }
      // 注册完直接去账户页拿发布令牌 —— 那才是他下一步真正要做的事
      router.push(href(locale, mode === 'signup' ? '/account' : '/stories'));
      router.refresh();
    } catch {
      setError(t(locale, 'auth.err.network'));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit} className="w-full max-w-sm space-y-4">
      <input
        type="email" required value={email} placeholder={t(locale, 'auth.email')}
        autoComplete="email" autoFocus
        onChange={(e) => setEmail(e.target.value)}
        className="w-full rounded-xl border border-white/15 bg-white/5 px-4 py-3
          outline-none focus:border-accentBright"
      />
      <input
        type="password" required minLength={8} value={password}
        autoComplete={mode === 'signup' ? 'new-password' : 'current-password'}
        placeholder={t(locale,
          mode === 'signup' ? 'auth.password.new' : 'auth.password')}
        onChange={(e) => setPassword(e.target.value)}
        className="w-full rounded-xl border border-white/15 bg-white/5 px-4 py-3
          outline-none focus:border-accentBright"
      />
      {error && <p className="text-sm text-red-400">{error}</p>}
      <button
        disabled={busy}
        className="w-full rounded-xl bg-accentBright py-3 font-medium text-ink
          disabled:opacity-50"
      >
        {busy ? t(locale, 'auth.busy')
          : t(locale, mode === 'signup' ? 'auth.submit.signup' : 'auth.submit.login')}
      </button>
    </form>
  );
}
