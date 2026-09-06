'use client';

import { useState } from 'react';

/** 用户在网页上敲入 App 显示的那串码，确认这台机器 */
export default function LinkDeviceForm({ labels }: {
  labels: {
    placeholder: string; submit: string; busy: string; done: string;
  };
}) {
  const [code, setCode] = useState('');
  const [state, setState] = useState<'idle' | 'busy' | 'done'>('idle');
  const [err, setErr] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setState('busy');
    setErr(null);
    const res = await fetch('/api/device/approve', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ code }),
    });
    const j = await res.json().catch(() => ({}));
    if (res.ok) { setState('done'); return; }
    setErr(j.error ?? '确认失败');
    setState('idle');
  }

  if (state === 'done') {
    return (
      <p className="mt-8 rounded-xl border border-accentBright/40
        bg-accentBright/10 px-5 py-4 text-sm text-accentBright">
        {labels.done}
      </p>
    );
  }

  return (
    <form onSubmit={submit} className="mt-8">
      <input
        value={code}
        onChange={(e) => setCode(e.target.value)}
        placeholder={labels.placeholder}
        autoFocus
        autoCapitalize="characters"
        className="w-full rounded-xl border border-white/15 bg-transparent
          px-5 py-4 text-center text-2xl tracking-[0.3em]
          placeholder:text-base placeholder:tracking-normal placeholder:text-muted"
      />
      <button
        type="submit"
        disabled={state === 'busy' || code.trim().length < 8}
        className="mt-4 w-full rounded-xl bg-accentBright py-3 font-medium
          text-ink disabled:opacity-50"
      >
        {state === 'busy' ? labels.busy : labels.submit}
      </button>
      {err && <p className="mt-3 text-sm text-red-400">{err}</p>}
    </form>
  );
}
