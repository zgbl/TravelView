'use client';

import { useState } from 'react';

/** 设置公开主页地址。没设过的时候这是账户页最该被看见的东西。 */
export default function HandleEditor({
  initial, site, labels,
}: {
  initial: string;
  site: string;
  labels: {
    title: string; hint: string; save: string; saved: string;
    taken: string; bad: string; open: string;
  };
}) {
  const [handle, setHandle] = useState(initial);
  const [saved, setSaved] = useState(initial);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function save() {
    setBusy(true);
    setErr(null);
    const res = await fetch('/api/handle', {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ handle }),
    });
    const j = await res.json().catch(() => ({}));
    setBusy(false);
    if (res.ok) { setSaved(j.handle); return; }
    setErr(j.error === 'TAKEN' ? labels.taken : labels.bad);
  }

  return (
    <section className="mt-6 rounded-2xl border border-white/12 p-6">
      <h2 className="text-sm font-medium">{labels.title}</h2>
      <div className="mt-3 flex items-center gap-2">
        <span className="text-sm text-muted">{site}/u/</span>
        <input
          value={handle}
          onChange={(e) => setHandle(e.target.value.toLowerCase())}
          className="min-w-0 flex-1 rounded-lg border border-white/15
            bg-transparent px-3 py-2 text-sm"
        />
        <button
          onClick={save}
          disabled={busy || !handle || handle === saved}
          className="rounded-lg bg-accentBright px-4 py-2 text-sm font-medium
            text-ink disabled:opacity-40"
        >
          {handle === saved && saved ? labels.saved : labels.save}
        </button>
      </div>
      {err && <p className="mt-2 text-xs text-red-400">{err}</p>}
      <p className="mt-2 text-xs text-muted">{labels.hint}</p>
      {saved && (
        <a href={`/u/${saved}`} className="mt-3 inline-block text-xs
          text-accentBright hover:underline">
          {labels.open} →
        </a>
      )}
    </section>
  );
}
