'use client';

import { useState } from 'react';
import { t, type Locale } from '@/lib/i18n';

export default function NameEditor({
  initial, locale = 'zh',
}: { initial: string; locale?: Locale }) {
  const [name, setName] = useState(initial);
  const [state, setState] = useState<'idle' | 'busy' | 'done'>('idle');

  async function save() {
    setState('busy');
    await fetch('/api/me', {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ name }),
    });
    setState('done');
    setTimeout(() => setState('idle'), 2000);
  }

  return (
    <div className="mt-6 rounded-2xl border border-white/12 p-6">
      <label className="text-sm">{t(locale, 'account.name')}</label>
      <div className="mt-3 flex gap-2">
        <input
          value={name} maxLength={40}
          onChange={(e) => setName(e.target.value)}
          className="flex-1 rounded-xl border border-white/15 bg-white/5 px-4 py-2.5
            text-sm outline-none focus:border-accentBright"
        />
        <button
          onClick={save} disabled={state === 'busy'}
          className="rounded-xl bg-accentBright px-5 text-sm font-medium text-ink
            disabled:opacity-50"
        >
          {state === 'done' ? t(locale, 'account.saved') : t(locale, 'account.save')}
        </button>
      </div>
      <p className="mt-2 text-xs text-muted">{t(locale, 'account.name.hint')}</p>
    </div>
  );
}
