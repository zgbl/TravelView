import { headers } from 'next/headers';
import type { Locale } from './i18n';

/**
 * 读当前语言。语言由 middleware 通过 x-locale 请求头传进来。
 *
 * **只能在服务端组件里用。** 客户端要用语言的话，由父组件当 prop 传下去 ——
 * 这也是为什么 t()/href() 留在纯的 i18n.ts 里。
 */
export async function getLocale(): Promise<Locale> {
  const h = await headers();
  return h.get('x-locale') === 'en' ? 'en' : 'zh';
}
