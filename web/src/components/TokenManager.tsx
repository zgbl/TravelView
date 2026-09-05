'use client';

import { useState } from 'react';

/**
 * 发布令牌。桌面端拿它上传，**不需要在 App 里存密码**。
 * 令牌只在生成时显示一次。
 */
export default function TokenManager() {
  const [token, setToken] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function create() {
    setBusy(true);
    const res = await fetch('/api/tokens', { method: 'POST' });
    const j = await res.json();
    setToken(j.token ?? null);
    setBusy(false);
  }

  return (
    <div className="mt-8 rounded-2xl border border-white/12 p-6">
      <h2 className="text-sm font-medium">桌面端发布令牌</h2>
      <p className="mt-2 text-xs leading-relaxed text-muted">
        在 TravelView 桌面端的设置里粘贴这个令牌，就能直接发布。
        它只在生成时显示一次，丢了就再生成一个。
      </p>
      {token ? (
        <div className="mt-4">
          <code className="block break-all rounded-xl bg-black/40 p-3 text-xs">
            {token}
          </code>
          <button
            onClick={() => navigator.clipboard.writeText(token)}
            className="mt-3 rounded-lg border border-white/15 px-4 py-1.5 text-xs"
          >
            复制
          </button>
        </div>
      ) : (
        <button
          onClick={create}
          disabled={busy}
          className="mt-4 rounded-lg bg-white/10 px-4 py-2 text-sm disabled:opacity-50"
        >
          {busy ? '正在生成...' : '生成新令牌'}
        </button>
      )}
    </div>
  );
}
