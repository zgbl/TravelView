'use client';

import { useEffect, useState } from 'react';
import { t, type Locale } from '@/lib/i18n';

/**
 * 尽力猜访客这台 Mac 是 Apple 芯片还是 Intel，对不上就直说。
 *
 * **猜不到就什么都不显示** —— 宁可少说一句，也不要猜错了吓人一跳。
 * 服务端拿不到这个信息: macOS 的 User-Agent 里根本没有架构
 * （Chrome 早就把 UA 冻住了，Safari 从来就没报过），
 * 所以只能在浏览器里问:
 *
 *   1. `navigator.userAgentData.getHighEntropyValues(['architecture'])`
 *      —— Chromium 系才有，返回 'arm' / 'x86'，最准
 *   2. 兜底看 WebGL 报出来的 GPU 型号（Safari 上常被抹掉，抹掉就算了）
 */
export default function MacArchHint({ arch, locale }: {
  arch: 'universal' | 'arm64' | 'x64' | null;
  locale: Locale;
}) {
  const [cpu, setCpu] = useState<'arm' | 'x86' | null>(null);

  useEffect(() => {
    let alive = true;
    (async () => {
      let found: 'arm' | 'x86' | null = null;
      try {
        const uaData = (navigator as unknown as {
          userAgentData?: { getHighEntropyValues?: (k: string[]) => Promise<{ architecture?: string }> };
        }).userAgentData;
        if (uaData?.getHighEntropyValues) {
          const v = await uaData.getHighEntropyValues(['architecture']);
          if (v.architecture === 'arm') found = 'arm';
          else if (v.architecture === 'x86') found = 'x86';
        }
      } catch { /* 权限或浏览器不支持，走兜底 */ }

      if (!found) {
        try {
          const gl = document.createElement('canvas').getContext('webgl');
          const ext = gl?.getExtension('WEBGL_debug_renderer_info');
          const r = ext && gl
            ? String(gl.getParameter(ext.UNMASKED_RENDERER_WEBGL))
            : '';
          if (/Apple M\d/i.test(r)) found = 'arm';
          else if (/Intel|AMD|Radeon/i.test(r)) found = 'x86';
        } catch { /* 没有 WebGL 就认命 */ }
      }
      if (alive) setCpu(found);
    })();
    return () => { alive = false; };
  }, []);

  if (!cpu || !arch || arch === 'universal') return null;
  const mismatch = (cpu === 'x86' && arch === 'arm64')
    || (cpu === 'arm' && arch === 'x64');
  if (!mismatch) return null;

  return (
    <p className="mt-3 rounded-lg border border-amber-400/30 bg-amber-400/10
      px-3 py-2 text-xs leading-relaxed text-amber-200">
      {t(locale, arch === 'arm64' ? 'dl.arch.mismatch.arm64' : 'dl.arch.mismatch.x64')}
    </p>
  );
}
