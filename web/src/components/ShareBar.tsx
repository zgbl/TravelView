'use client';

import { useEffect, useState } from 'react';
import { t, type Locale } from '@/lib/i18n';

/**
 * 分享条。
 *
 * 两个平台的分享方式**根本不同**，不能套同一个按钮:
 *   - Facebook 有分享器地址，开个窗口就行
 *   - 微信没有网页分享接口。唯一可靠的路径是**二维码**:
 *     手机扫码打开，再用微信自己的菜单转发。
 *     任何声称能一键分享到微信的网页代码都是假的。
 *
 * 还有第三个按钮: 复制链接。听起来平淡，实际使用率通常最高 ——
 * 用户要发的地方（小红书、微博、短信、邮件）远不止那两个。
 */
export default function ShareBar({
  url,
  title,
  locale = 'zh',
}: {
  url: string;
  title: string;
  locale?: Locale;
}) {
  const [copied, setCopied] = useState(false);
  const [qr, setQr] = useState<string | null>(null);
  const [showQr, setShowQr] = useState(false);

  useEffect(() => {
    if (!showQr || qr) return;
    // 按需加载，不为一个不一定会点的按钮拖慢首屏
    import('qrcode').then((m) =>
      m.toDataURL(url, { width: 480, margin: 1 }).then(setQr).catch(() => {}),
    );
  }, [showQr, qr, url]);

  async function copy() {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // 剪贴板可能被浏览器拒绝（非 https、权限），别假装成功
      window.prompt(t(locale, 'share.copy.manual'), url);
    }
  }

  function facebook() {
    const u = `https://www.facebook.com/sharer/sharer.php?u=${
      encodeURIComponent(url)}`;
    window.open(u, 'fb-share', 'width=640,height=640,noopener');
  }

  return (
    <>
      <div className="fixed inset-x-0 bottom-0 z-40 flex justify-center
        bg-gradient-to-t from-ink via-ink/90 to-transparent px-4 pb-5 pt-10">
        <div className="flex items-center gap-2 rounded-full border
          border-white/12 bg-ink/90 px-2 py-2 backdrop-blur">
          <span className="hidden px-3 text-sm text-muted sm:block">
            {t(locale, 'share.label')}
          </span>

          <button onClick={facebook} className={btn}>
            <FbIcon /> Facebook
          </button>

          <button onClick={() => setShowQr(true)} className={btn}>
            <WeChatIcon /> {t(locale, 'share.wechat')}
          </button>

          <button onClick={copy} className={`${btn} bg-accentBright text-ink`}>
            {copied ? t(locale, 'share.copied') : t(locale, 'share.copy')}
          </button>
        </div>
      </div>

      {showQr && (
        <div
          onClick={() => setShowQr(false)}
          className="fixed inset-0 z-50 flex items-center justify-center
            bg-black/85 px-6"
        >
          <div
            onClick={(e) => e.stopPropagation()}
            className="w-full max-w-xs rounded-2xl bg-paper p-6 text-center
              text-ink"
          >
            <div className="text-sm font-medium">{t(locale, 'share.wechat.how')}</div>
            {qr ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={qr} alt={title} className="mx-auto mt-4 w-full rounded-lg" />
            ) : (
              <div className="mt-4 h-56 animate-pulse rounded-lg bg-black/10" />
            )}
            <div className="mt-3 break-all text-[11px] text-ink/60">{url}</div>
            <button
              onClick={() => setShowQr(false)}
              className="mt-4 text-sm text-ink/60 hover:text-ink"
            >
              {t(locale, 'share.close')}
            </button>
          </div>
        </div>
      )}
    </>
  );
}

const btn =
  'flex items-center gap-1.5 rounded-full px-4 py-2 text-sm ' +
  'text-paper transition hover:bg-white/10';

function FbIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M22 12a10 10 0 1 0-11.6 9.9v-7H7.9V12h2.5V9.8c0-2.5 1.5-3.9
        3.8-3.9 1.1 0 2.2.2 2.2.2v2.5h-1.3c-1.2 0-1.6.8-1.6 1.6V12h2.8l-.4 2.9h-2.4v7A10
        10 0 0 0 22 12z" />
    </svg>
  );
}

function WeChatIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M3 3h8v8H3V3zm2 2v4h4V5H5zm8-2h8v8h-8V3zm2 2v4h4V5h-4zM3 13h8v8H3v-8zm2
        2v4h4v-4H5zm10-2h2v2h-2v-2zm4 0h2v2h-2v-2zm-4 4h2v2h-2v-2zm4 0h2v4h-4v-2h2v-2z" />
    </svg>
  );
}
