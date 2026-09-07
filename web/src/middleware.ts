import { NextResponse, type NextRequest } from 'next/server';

/**
 * 中英双语的路由。
 *
 * 语言体现在**路径前缀**上（/zh /en），不是 cookie —— 因为这个产品的核心动作
 * 是把链接分享出去: 链接自带语言，发给外国朋友打开就是英文；
 * 搜索引擎也能把两种语言分别收录。cookie 方案做不到这两点。
 *
 * 实现上用 rewrite 而不是把所有页面挪进 [locale] 目录:
 * 路径保持 /zh/pricing，内部仍然渲染 /pricing，语言通过请求头传给页面。
 * 少动几十个文件，也就少了几十个出错的机会。
 *
 * 没带前缀的老链接按浏览器语言 302 到对应版本 —— **已经分享出去的链接不能失效。**
 */
import { locales, type Locale } from './lib/i18n';

const DEFAULT: Locale = 'zh';

export function middleware(req: NextRequest) {
  const { pathname, search } = req.nextUrl;

  // 静态资源、API、图片一律不碰
  if (/^\/(api|_next|media|favicon|robots|sitemap)/.test(pathname)) {
    return NextResponse.next();
  }

  const seg = pathname.split('/')[1];
  if ((locales as readonly string[]).includes(seg)) {
    const rest = pathname.slice(seg.length + 1) || '/';
    const url = req.nextUrl.clone();
    url.pathname = rest;
    // **路径要塞进请求头**，不是响应头 ——
    // 服务端组件读的是请求头，写在响应上它看不到
    const reqHeaders = new Headers(req.headers);
    reqHeaders.set('x-locale', seg);
    reqHeaders.set('x-pathname', rest);
    const res = NextResponse.rewrite(url, { request: { headers: reqHeaders } });
    // 响应头也留一份: 原来只写响应头，改动时两边都留着最稳
    res.headers.set('x-locale', seg);
    // 记住选择，下次访问裸链接直接给他熟悉的那一版
    res.cookies.set('locale', seg, { maxAge: 60 * 60 * 24 * 365, path: '/' });
    return res;
  }

  const saved = req.cookies.get('locale')?.value;
  const accept = req.headers.get('accept-language') ?? '';
  const guess: Locale = saved === 'en' || saved === 'zh'
    ? saved
    : /^zh|,zh/i.test(accept) ? 'zh' : accept ? 'en' : DEFAULT;

  const url = req.nextUrl.clone();
  url.pathname = `/${guess}${pathname === '/' ? '' : pathname}`;
  url.search = search;
  return NextResponse.redirect(url);
}

export const config = {
  matcher: ['/((?!api|_next/static|_next/image|media|favicon.ico).*)'],
};
