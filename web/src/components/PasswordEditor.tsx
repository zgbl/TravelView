'use client';

import { useState } from 'react';
import { t, type Locale } from '@/lib/i18n';

/**
 * 改密码。三个框：当前密码、新密码、再输一遍。
 *
 * "再输一遍"在客户端就比对掉 —— 打错字这种事不值得跑一趟服务器，
 * 而且服务器也没法替用户判断哪个才是他想要的那个。
 */
export default function PasswordEditor({ locale = 'zh' }: { locale?: Locale }) {
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [again, setAgain] = useState('');
  const [state, setState] = useState<'idle' | 'busy' | 'done'>('idle');
  const [error, setError] = useState<string | null>(null);

  const box = `w-full rounded-xl border border-white/15 bg-white/5 px-4 py-2.5
    text-sm outline-none focus:border-accentBright`;

  async function save() {
    setError(null);
    if (next !== again) {
      setError(t(locale, 'account.password.mismatch'));
      return;
    }
    setState('busy');
    const res = await fetch('/api/account/password', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ current, next }),
    });
    if (!res.ok) {
      const j = await res.json().catch(() => null);
      setError(j?.error ?? t(locale, 'account.password.failed'));
      setState('idle');
      return;
    }
    setCurrent(''); setNext(''); setAgain('');
    setState('done');
    setTimeout(() => setState('idle'), 2500);
  }

  return (
    <div className="mt-6 rounded-2xl border border-white/12 p-6">
      <label className="text-sm">{t(locale, 'account.password')}</label>
      <div className="mt-3 space-y-2">
        <input
          type="password" value={current} autoComplete="current-password"
          placeholder={t(locale, 'account.password.current')}
          onChange={(e) => setCurrent(e.target.value)} className={box}
        />
        <input
          type="password" value={next} autoComplete="new-password"
          placeholder={t(locale, 'account.password.new')}
          onChange={(e) => setNext(e.target.value)} className={box}
        />
        <input
          type="password" value={again} autoComplete="new-password"
          placeholder={t(locale, 'account.password.again')}
          onChange={(e) => setAgain(e.target.value)} className={box}
        />
      </div>
      {error && <p className="mt-2 text-xs text-red-400">{error}</p>}
      <button
        onClick={save}
        disabled={state === 'busy' || !current || !next}
        className="mt-3 rounded-xl bg-accentBright px-5 py-2 text-sm
          font-medium text-ink disabled:opacity-50"
      >
        {state === 'done'
          ? t(locale, 'account.saved')
          : t(locale, 'account.password.change')}
      </button>
      <p className="mt-2 text-xs text-muted">
        {t(locale, 'account.password.hint')}
      </p>
    </div>
  );
}
