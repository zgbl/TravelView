'use client';

import { useState } from 'react';

/**
 * 后台上传新版本。
 *
 * **直接用原生 form + fetch**，不引任何上传组件: 一个安装包一次，
 * 站长自己用，进度条都不需要 —— 需要的是"传没传上去"这一个答案。
 */
export default function ReleaseUpload() {
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [ok, setOk] = useState(false);

  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = e.currentTarget;
    setBusy(true);
    setMsg(null);
    try {
      const res = await fetch('/api/admin/releases', {
        method: 'POST',
        body: new FormData(form),
      });
      const j = await res.json().catch(() => ({}));
      setOk(res.ok);
      setMsg(res.ok ? '已上传' : (j.error ?? `失败 (${res.status})`));
      if (res.ok) form.reset();
    } catch (err) {
      setOk(false);
      setMsg(String(err));
    } finally {
      setBusy(false);
    }
  }

  const field = 'w-full rounded-lg border border-white/15 bg-white/[.04] ' +
    'px-3 py-2 text-sm outline-none focus:border-white/35';

  return (
    <form onSubmit={submit} className="grid gap-3 md:grid-cols-2">
      <label className="text-xs text-muted">
        平台
        <select name="platform" className={field} defaultValue="macos">
          <option value="macos">macOS</option>
          <option value="windows">Windows</option>
          <option value="android">Android</option>
          <option value="ios">iOS</option>
        </select>
      </label>

      <label className="text-xs text-muted">
        版本号（1.2.0）
        <input name="version" required placeholder="1.0.0" className={field} />
      </label>

      <label className="text-xs text-muted md:col-span-2">
        安装包
        <input type="file" name="file" className={field} />
      </label>

      <label className="text-xs text-muted md:col-span-2">
        或者外部下载地址（App Store / 商店链接，https）
        <input name="externalUrl" placeholder="https://apps.apple.com/..."
          className={field} />
      </label>

      <label className="text-xs text-muted md:col-span-2">
        更新说明
        <textarea name="notes" rows={3} className={field} />
      </label>

      <label className="flex items-center gap-2 text-sm md:col-span-2">
        {/* **默认勾上。** 传一个新版本却不让用户下载到，
            是这个表单里最没道理的默认值 */}
        <input type="checkbox" name="current" defaultChecked />
        设为当前版本（下载页给的就是它）
      </label>

      <div className="flex items-center gap-3 md:col-span-2">
        <button disabled={busy}
          className="rounded-full bg-accentBright px-6 py-2 text-sm font-medium
            text-ink disabled:opacity-50">
          {busy ? '上传中…' : '上传'}
        </button>
        {msg && (
          <span className={`text-sm ${ok ? 'text-accentBright' : 'text-red-400'}`}>
            {msg}
          </span>
        )}
      </div>
    </form>
  );
}
