'use client';

import { usePathname, useRouter } from 'next/navigation';

/**
 * 中 / EN 切换。**留在当前页面**切换，不是跳回首页 ——
 * 正在看一篇 Story 的人切语言，想要的是这一篇的另一种语言。
 */
export default function LangSwitch({ locale }: { locale: 'zh' | 'en' }) {
  const path = usePathname() ?? '/';
  const router = useRouter();
  const other = locale === 'zh' ? 'en' : 'zh';

  function go() {
    const rest = /^\/(zh|en)(\/|$)/.test(path)
      ? path.replace(/^\/(zh|en)/, '')
      : path;
    router.push(`/${other}${rest || ''}`);
  }

  return (
    <button
      onClick={go}
      className="text-white/70 transition hover:text-white"
      aria-label={locale === 'zh' ? 'Switch to English' : '切换到中文'}
    >
      {locale === 'zh' ? 'EN' : '中文'}
    </button>
  );
}
