'use client';

import { useState } from 'react';

/**
 * 后台上传新版本。
 *
 * **用 XMLHttpRequest，不用 fetch。** fetch 没有任何"已发送多少"的回调，
 * 54MB 的安卓包传十分钟，页面只能干瞪着"上传中…" —— 到底是慢、
 * 是卡住、还是早就被拒了，站长一点都看不出来。XHR 的
 * `upload.onprogress` 是唯一能拿到上行进度的东西。
 *
 * 分三个阶段，因为它们是三件不同的事，混成一句"上传中"就是在骗人：
 *   1. 上传中    —— 文件在往上走，能报百分比和速度
 *   2. 校验落盘  —— 字节已经收完，服务器在算 sha256、写磁盘
 *   3. 结束      —— 成功或失败，失败要说清是哪一种
 */

type Phase = 'idle' | 'uploading' | 'saving' | 'done' | 'error';

function mb(n: number) {
  return (n / 1048576).toFixed(1);
}

export default function ReleaseUpload() {
  const [platform, setPlatform] = useState('macos');
  const [busy, setBusy] = useState(false);
  const [phase, setPhase] = useState<Phase>('idle');
  const [pct, setPct] = useState(0);
  const [loaded, setLoaded] = useState(0);
  const [total, setTotal] = useState(0);
  const [rate, setRate] = useState(0);
  const [eta, setEta] = useState<number | null>(null);
  const [elapsed, setElapsed] = useState(0);
  const [msg, setMsg] = useState<string | null>(null);
  const [ok, setOk] = useState(false);

  function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = e.currentTarget;
    const fd = new FormData(form);
    const file = fd.get('file');
    const size = file instanceof File ? file.size : 0;

    setBusy(true);
    setMsg(null);
    setOk(false);
    setPct(0);
    setLoaded(0);
    setRate(0);
    setEta(null);
    setPhase(size > 0 ? 'uploading' : 'saving');
    setTotal(size);

    const started = Date.now();
    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/api/admin/releases');
    xhr.timeout = 30 * 60 * 1000;   // 30 分钟: 慢速上行传大包够用了

    xhr.upload.onprogress = (ev) => {
      if (!ev.lengthComputable) return;
      const secs = Math.max((Date.now() - started) / 1000, 0.001);
      setLoaded(ev.loaded);
      setTotal(ev.total);
      setPct(Math.round((ev.loaded / ev.total) * 100));
      setRate(ev.loaded / secs);
      setEta(ev.loaded > 0
        ? Math.round(((ev.total - ev.loaded) / (ev.loaded / secs)))
        : null);
      setElapsed(Math.round(secs));
    };
    // 最后一个字节发出去了，但服务端还要读完 body、算 sha256、写磁盘
    xhr.upload.onload = () => {
      setPhase('saving');
      setPct(100);
    };

    xhr.onload = () => {
      setBusy(false);
      setPhase(xhr.status >= 200 && xhr.status < 300 ? 'done' : 'error');
      let j: { error?: string } = {};
      try { j = JSON.parse(xhr.responseText); } catch { /* 可能是一页 HTML */ }
      setOk(xhr.status >= 200 && xhr.status < 300);
      if (xhr.status === 413) {
        setMsg('被服务器拒了：文件超过体积上限（nginx 512m / Cloudflare 100MB）。'
          + '再大的包请传 R2 后用「外部下载地址」。');
      } else if (xhr.status === 404) {
        setMsg('404 —— 会话过期了，重新登录后台再来一次');
      } else {
        setMsg(j.error ?? `失败 (HTTP ${xhr.status})`);
      }
      if (xhr.status >= 200 && xhr.status < 300) form.reset();
    };
    xhr.onerror = () => {
      setBusy(false);
      setPhase('error');
      setOk(false);
      // 这里的"网络错误"是真网络错误: 连接断了, 不是服务器回的错
      setMsg('连接断了（网络或代理中断），文件没有传完');
    };
    xhr.ontimeout = () => {
      setBusy(false);
      setPhase('error');
      setOk(false);
      setMsg('超过 30 分钟还没传完，已放弃');
    };

    xhr.send(fd);
  }

  const field = 'w-full rounded-lg border border-white/15 bg-white/[.04] ' +
    'px-3 py-2 text-sm outline-none focus:border-white/35';

  return (
    <form onSubmit={submit} className="grid gap-3 md:grid-cols-2">
      <label className="text-xs text-muted">
        平台
        <select name="platform" className={field} value={platform}
          onChange={(e) => setPlatform(e.target.value)}>
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

      {/* 架构只在 macOS 上有意义 —— 在 M1 上编出来的包如果只含 arm64，
          Intel 用户装了根本打不开，而页面不说的话他只会以为我们发了个坏包。
          所以这里让上传的人如实声明。 */}
      {platform === 'macos' && (
        <label className="text-xs text-muted md:col-span-2">
          架构（macOS 才需要声明）
          <select name="arch" className={field} defaultValue="universal">
            <option value="universal">通用 —— Apple 芯片 + Intel（Flutter release 默认）</option>
            <option value="arm64">仅 Apple 芯片（M 系列）</option>
            <option value="x64">仅 Intel</option>
          </select>
          <span className="mt-1 block text-[11px] text-muted/80">
            不确定就查包里的二进制：<code>lipo -archs TravelView.app/Contents/MacOS/TravelView</code>
            —— 输出了两个架构就是通用，只有一个就照实选。
          </span>
        </label>
      )}

      <label className="text-xs text-muted md:col-span-2">
        安装包
        <input type="file" name="file" className={field} />
      </label>

      <label className="text-xs text-muted md:col-span-2">
        或者外部下载地址（R2 直链 / App Store / 商店链接，https）
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

      <div className="md:col-span-2">
        <div className="flex items-center gap-3">
          <button disabled={busy}
            className="rounded-full bg-accentBright px-6 py-2 text-sm font-medium
              text-ink disabled:opacity-50">
            {phase === 'uploading' ? '上传中…'
              : phase === 'saving' ? '服务器处理中…' : '上传'}
          </button>
          {msg && (
            <span className={`text-sm ${ok ? 'text-accentBright' : 'text-red-400'}`}>
              {msg}
            </span>
          )}
        </div>

        {/* 进度条: 传大包时这一条就是全部的反馈 */}
        {(phase === 'uploading' || phase === 'saving') && (
          <div className="mt-3">
            <div className="h-1.5 w-full overflow-hidden rounded-full bg-white/10">
              <div
                className="h-full rounded-full bg-accentBright transition-[width]
                  duration-200"
                style={{ width: `${phase === 'saving' ? 100 : pct}%` }}
              />
            </div>
            <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted">
              {phase === 'uploading' ? (
                <>
                  <span className="text-paper">{pct}%</span>
                  <span>{mb(loaded)} / {mb(total)} MB</span>
                  {rate > 0 && <span>{mb(rate)} MB/s</span>}
                  {eta !== null && eta > 0 && (
                    <span>剩余约 {eta >= 60
                      ? `${Math.floor(eta / 60)} 分 ${eta % 60} 秒`
                      : `${eta} 秒`}</span>
                  )}
                  <span>已用 {elapsed} 秒</span>
                </>
              ) : (
                <span>
                  字节已收完（{mb(total)} MB），服务器正在校验并落盘 ——
                  这一步不再有进度可报，54MB 大约几秒
                </span>
              )}
            </div>
          </div>
        )}
      </div>
    </form>
  );
}
