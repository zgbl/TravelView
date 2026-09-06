'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

type U = {
  id: string; email: string; name: string | null; created_at: string;
  is_admin: boolean; banned: boolean; self: boolean;
  story_credits: number; subscription_status: string | null;
  stories: string; views: string;
};

export default function UserRow({ u }: { u: U }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);

  async function act(action: string, amount?: number) {
    setBusy(true);
    const res = await fetch('/api/admin/users', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ userId: u.id, action, amount }),
    });
    setBusy(false);
    if (!res.ok) {
      alert((await res.json().catch(() => ({}))).error ?? '操作失败');
      return;
    }
    router.refresh();
  }

  return (
    <tr className={`border-b border-white/8 ${u.banned ? 'opacity-45' : ''}`}>
      <td className="py-3">
        <div className="flex items-center gap-2">
          <span>{u.name ?? u.email.split('@')[0]}</span>
          {u.is_admin && <Tag>管理员</Tag>}
          {u.banned && <Tag tone="warn">已停用</Tag>}
          {u.subscription_status === 'active' && <Tag>订阅中</Tag>}
        </div>
        <div className="text-xs text-muted">{u.email}</div>
      </td>
      <td className="py-3 text-right">{u.stories}</td>
      <td className="py-3 text-right">{u.views}</td>
      <td className="py-3 text-right">{u.story_credits}</td>
      <td className="py-3 text-right text-xs text-muted">{u.created_at}</td>
      <td className="py-3 text-right">
        <div className="flex justify-end gap-1.5">
          <Btn disabled={busy} onClick={() => act('add_credits', 5)}>+5 额度</Btn>
          {u.is_admin ? (
            <Btn disabled={busy || u.self}
              onClick={() => act('revoke_admin')}>撤管理员</Btn>
          ) : (
            <Btn disabled={busy} onClick={() => act('grant_admin')}>设管理员</Btn>
          )}
          {u.banned ? (
            <Btn disabled={busy} onClick={() => act('unban')}>恢复</Btn>
          ) : (
            <Btn disabled={busy || u.self} tone="warn"
              onClick={() => {
                if (confirm(`停用 ${u.email}？会吊销他的全部发布令牌。`)) {
                  act('ban');
                }
              }}>停用</Btn>
          )}
        </div>
      </td>
    </tr>
  );
}

function Btn({ children, tone, ...rest }: {
  children: React.ReactNode; tone?: 'warn';
} & React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      {...rest}
      className={`rounded-lg border px-2.5 py-1 text-xs transition
        disabled:opacity-30 ${tone === 'warn'
          ? 'border-red-400/30 text-red-300 hover:bg-red-400/10'
          : 'border-white/15 text-muted hover:bg-white/10 hover:text-paper'}`}
    >
      {children}
    </button>
  );
}

function Tag({ children, tone }: { children: React.ReactNode; tone?: 'warn' }) {
  return (
    <span className={`rounded px-1.5 py-0.5 text-[10px] ${tone === 'warn'
      ? 'bg-red-400/15 text-red-300' : 'bg-accentBright/15 text-accentBright'}`}>
      {children}
    </span>
  );
}
