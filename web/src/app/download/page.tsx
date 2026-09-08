import { headers } from 'next/headers';
import NavBar from '@/components/NavBar';
import SiteFooter from '@/components/SiteFooter';
import { getLocale } from '@/lib/i18n.server';
import { t } from '@/lib/i18n';
import {
  currentReleases, guessPlatform, humanBytes, platformLabel, platforms,
  type Platform, type Release,
} from '@/lib/releases';

export const dynamic = 'force-dynamic';

/**
 * 下载页。
 *
 * **四个平台一直都在**，哪怕某个平台还没发布 —— 一个访客想知道的
 * 第一件事就是"有没有我的系统"，把没做完的平台藏起来，
 * 他只会以为我们不支持，然后走掉。没发布的写"还没发布"。
 *
 * 猜到的系统排在最前面并高亮，但**不自动跳转下载** ——
 * 猜错了直接给他一个下错的文件，比让他自己点一下糟得多。
 */
export default async function Download() {
  const L = await getLocale();
  const ua = (await headers()).get('user-agent') ?? '';
  const mine = guessPlatform(ua);
  const rows = await currentReleases();
  const byPlatform = new Map(rows.map((r) => [r.platform, r]));

  // 猜到的系统提到最前
  const order = [...platforms].sort((a, b) =>
    (a === mine ? -1 : 0) - (b === mine ? -1 : 0));

  return (
    <main className="min-h-screen bg-ink text-paper">
      <NavBar />
      <section className="mx-auto max-w-4xl px-6 py-16">
        <h1 className="text-[clamp(28px,4vw,44px)] font-semibold tracking-tight">
          {t(L, 'dl.title')}
        </h1>
        <p className="mt-3 max-w-2xl text-sm leading-relaxed text-muted">
          {t(L, 'dl.sub')}
        </p>

        {rows.length === 0 && (
          <p className="mt-8 rounded-xl border border-white/10 bg-white/[.03]
            px-5 py-4 text-sm text-muted">
            {t(L, 'dl.none')}
          </p>
        )}

        <div className="mt-10 grid gap-4">
          {order.map((p) => (
            <Card key={p} platform={p} rel={byPlatform.get(p)}
              mine={p === mine} locale={L} />
          ))}
        </div>

        <p className="mt-10 text-xs leading-relaxed text-muted">
          {t(L, 'dl.mobile.note')}
        </p>
      </section>
      <SiteFooter />
    </main>
  );
}

function Card({
  platform, rel, mine, locale,
}: {
  platform: Platform; rel?: Release; mine: boolean;
  locale: Parameters<typeof t>[0];
}) {
  const has = !!rel;
  return (
    <div className={`rounded-2xl border p-5 transition
      ${mine ? 'border-accentBright/50 bg-accentBright/[.06]'
             : 'border-white/10 bg-white/[.03]'}`}>
      <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
        <Glyph platform={platform} />
        <div className="mr-auto">
          <div className="flex items-center gap-2">
            <span className="text-lg font-semibold">
              {platformLabel(platform)}
            </span>
            {mine && (
              <span className="rounded-full bg-accentBright px-2 py-0.5
                text-[10px] font-medium text-ink">
                {t(locale, 'dl.yours')}
              </span>
            )}
          </div>
          <div className="mt-0.5 text-xs text-muted">
            {has
              ? `${t(locale, 'dl.version')} ${rel!.version}` +
                (rel!.bytes ? ` · ${humanBytes(rel!.bytes)}` : '')
              : t(locale, 'dl.soon.b')}
          </div>
        </div>

        {has ? (
          <a
            href={rel!.externalUrl ?? `/api/releases/${rel!.id}/download`}
            className="rounded-full bg-accentBright px-6 py-2.5 text-sm
              font-medium text-ink transition hover:brightness-110"
          >
            {t(locale, 'dl.get')}
          </a>
        ) : (
          <span className="rounded-full border border-white/15 px-6 py-2.5
            text-sm text-muted">
            {t(locale, 'dl.soon')}
          </span>
        )}
      </div>

      {has && rel!.notes && (
        <p className="mt-4 whitespace-pre-line border-t border-white/10 pt-4
          text-xs leading-relaxed text-muted">
          {rel!.notes}
        </p>
      )}
      {/* 校验和只在有的时候出现，而且是可选中的等宽文本 ——
          它的唯一用途就是被复制去比对 */}
      {has && rel!.checksum && (
        <p className="mt-3 select-all break-all font-mono text-[10px] text-muted/70">
          sha256 {rel!.checksum}
        </p>
      )}
    </div>
  );
}

/// 平台标记。**不引外部图标库** —— 为四个小方块拉一个包不值得
function Glyph({ platform }: { platform: Platform }) {
  const ch = { macos: 'mac', windows: 'win', android: 'apk', ios: 'iOS' }[platform];
  return (
    <span className="flex h-11 w-11 items-center justify-center rounded-xl
      border border-white/12 bg-white/[.05] text-[11px] font-medium
      uppercase tracking-wide text-muted">
      {ch}
    </span>
  );
}
