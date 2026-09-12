'use client';

import { useEffect, useState } from 'react';
import { t, type Locale } from '@/lib/i18n';

/**
 * 分享条。
 *
 * **手机上第一优先是系统分享面板（navigator.share）。**
 *
 * 之前微信按钮弹的是二维码 —— 那在手机上是个死路：**用户只有一台手机，
 * 没法用自己的手机扫自己屏幕上的码。** 他想发给朋友，却被要求先变出
 * 第二台设备。二维码只在电脑上有意义（人在电脑前，用手机扫码带走）。
 *
 * 所以按环境分三条路，而不是所有人看同一排按钮：
 *
 *   1. **微信内置浏览器** —— 网页无法调起转发（没有 JS-SDK 就是不行，
 *      声称能做到的代码都是假的）。这里唯一诚实的做法是告诉他
 *      「点右上角的 ···」，并把那个位置指出来。
 *   2. **其它手机浏览器** —— `navigator.share()` 拉起系统分享面板，
 *      微信、微博、短信、AirDrop 全在里面，一次点击到位。
 *      这不是"假的一键分享微信"：我们不调微信的接口，是把内容交给
 *      操作系统，由用户在面板里挑微信。
 *   3. **电脑** —— 没有系统分享面板，才轮到二维码和 Facebook 分享器。
 *
 * 还有一个「复制链接」，三种环境下都留着。听起来平淡，实际使用率通常最高 ——
 * 用户要发的地方（小红书、微博、邮件、群公告）远不止那两个。
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
  const [inWeChat, setInWeChat] = useState(false);
  const [showWeChatHow, setShowWeChatHow] = useState(false);
  // 有没有系统分享面板。**必须在 useEffect 里探测**: 服务端渲染时
  // 没有 navigator，直接读会让首屏和水合后的 HTML 对不上。
  const [canShare, setCanShare] = useState(false);

  useEffect(() => {
    setCanShare(typeof navigator !== 'undefined' && !!navigator.share);
    setInWeChat(
      typeof navigator !== 'undefined' &&
        /MicroMessenger/i.test(navigator.userAgent),
    );
  }, []);

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

  /**
   * 交给系统分享面板。
   *
   * 用户按取消会抛 AbortError —— **那不是错误，是他改主意了**，
   * 什么都不用做，更不能弹一个"分享失败"去责备他。
   */
  async function shareNative() {
    try {
      await navigator.share({ title, url });
    } catch {
      /* 取消或被拒绝，静默 */
    }
  }

  function facebook() {
    const u = `https://www.facebook.com/sharer/sharer.php?u=${
      encodeURIComponent(url)}`;
    window.open(u, 'fb-share', 'width=640,height=640,noopener');
  }

  return (
    <>
      {/* 外层横跨整个视口底部，只是为了让药丸居中 + 加一层渐变。
          **必须 pointer-events-none**: 否则它会盖住地图右下角，
          按钮点不着、点击还被转给这里的分享按钮。 */}
      <div className="pointer-events-none fixed inset-x-0 bottom-0 z-40
        flex justify-center bg-gradient-to-t from-ink via-ink/90
        to-transparent px-4 pb-5 pt-10">
        <div className="pointer-events-auto flex items-center gap-2
          rounded-full border border-white/12 bg-ink/90 px-2 py-2 backdrop-blur">
          <span className="hidden px-3 text-sm text-muted sm:block">
            {t(locale, 'share.label')}
          </span>

          {inWeChat ? (
            // 微信里：唯一能做的就是把那个 ··· 指给他看
            <button onClick={() => setShowWeChatHow(true)} className={btn}>
              <WeChatIcon /> {t(locale, 'share.wechat.inapp')}
            </button>
          ) : canShare ? (
            // 手机：一次点击拉起系统面板，微信就在里面
            <button onClick={shareNative} className={btn}>
              <ShareIcon /> {t(locale, 'share.now')}
            </button>
          ) : (
            // 电脑：分享器 + 二维码才有意义
            <>
              <button onClick={facebook} className={btn}>
                <FbIcon /> Facebook
              </button>
              <button onClick={() => setShowQr(true)} className={btn}>
                <WeChatIcon /> {t(locale, 'share.wechat')}
              </button>
            </>
          )}

          <button onClick={copy} className={`${btn} bg-accentBright text-ink`}>
            {copied ? t(locale, 'share.copied') : t(locale, 'share.copy')}
          </button>
        </div>
      </div>

      {showWeChatHow && (
        <div
          onClick={() => setShowWeChatHow(false)}
          className="fixed inset-0 z-50 bg-black/85 px-6"
        >
          {/* 箭头指向右上角那个 ··· —— 光写"点右上角"，
              用户的眼睛还是得自己找一遍 */}
          <div className="absolute right-4 top-3 text-4xl text-paper">
            &#8598;
          </div>
          <div className="flex h-full items-center justify-center">
            <div
              onClick={(e) => e.stopPropagation()}
              className="w-full max-w-xs rounded-2xl bg-paper p-6 text-center
                text-ink"
            >
              <div className="text-sm font-medium leading-relaxed">
                {t(locale, 'share.wechat.inapp.how')}
              </div>
              <div className="mt-3 break-all text-[11px] text-ink/60">{url}</div>
              <button
                onClick={() => setShowWeChatHow(false)}
                className="mt-4 text-sm text-ink/60 hover:text-ink"
              >
                {t(locale, 'share.close')}
              </button>
            </div>
          </div>
        </div>
      )}

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

function ShareIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth="2" strokeLinecap="round"
      strokeLinejoin="round" aria-hidden>
      <path d="M4 12v7a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-7" />
      <path d="M12 3v13M8 7l4-4 4 4" />
    </svg>
  );
}

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
