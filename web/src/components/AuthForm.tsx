'use client';

import { useState } from 'react';
import { signIn } from 'next-auth/react';
import { useRouter } from 'next/navigation';

export default function AuthForm({ mode }: { mode: 'login' | 'signup' }) {
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
          setError((await res.json()).error ?? '注册失败');
          return;
        }
      }
      const r = await signIn('credentials', {
        email, password, redirect: false,
      });
      if (r?.error) {
        setError('邮箱或密码不对');
        return;
      }
      router.push('/stories');
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit} className="w-full max-w-sm space-y-4">
      <input
        type="email" required value={email} placeholder="邮箱"
        onChange={(e) => setEmail(e.target.value)}
        className="w-full rounded-xl border border-white/15 bg-white/5 px-4 py-3
          outline-none focus:border-accentBright"
      />
      <input
        type="password" required minLength={8} value={password}
        placeholder={mode === 'signup' ? '密码（至少 8 位）' : '密码'}
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
        {mode === 'signup' ? '创建账号' : '登录'}
      </button>
    </form>
  );
}
