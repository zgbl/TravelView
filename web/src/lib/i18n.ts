export type Locale = 'zh' | 'en';
export const locales: Locale[] = ['zh', 'en'];

/**
 * **这个文件必须是纯的** —— 客户端组件（AuthForm / LangSwitch）也要用 t()。
 * 一旦在这里 import next/headers，整个构建就会挂在
 * "You're importing a component that needs next/headers"。
 * 读请求头的部分单独放在 i18n.server.ts。
 */

/** 生成带语言前缀的链接。**站内所有 Link 都要经过它**，否则一点就掉出语言。 */
export function href(locale: Locale, path: string) {
  return `/${locale}${path === '/' ? '' : path}`;
}

type Dict = Record<string, { zh: string; en: string }>;

/**
 * 文案表。
 *
 * 刻意用一张扁平表而不是引第三方 i18n 库: 现在只有两种语言、一百来条文案，
 * 一个 t() 就够；等真需要复数、日期格式、按需加载时再换不迟。
 */
export const dict: Dict = {
  'nav.pricing': { zh: '价格', en: 'Pricing' },
  'nav.login': { zh: '登录', en: 'Log in' },
  'nav.start': { zh: '开始使用', en: 'Get started' },
  'nav.stories': { zh: '我的故事', en: 'My stories' },
  'nav.account': { zh: '账户', en: 'Account' },
  'nav.admin': { zh: '后台', en: 'Admin' },
  'nav.back': { zh: '返回', en: 'Back' },

  'auth.signup.title': { zh: '创建账号', en: 'Create your account' },
  'auth.signup.intro': {
    zh: '注册只用来发布和管理你的旅行故事。照片的识别、挑选、路线还原全都在你自己的电脑上完成，',
    en: 'An account is only for publishing and managing your travel stories. All the photo reading, curation and route reconstruction happens on your own computer — ',
  },
  'auth.signup.intro.strong': {
    zh: '原图一张都不会上传',
    en: 'your original photos are never uploaded',
  },
  'auth.login.title': { zh: '登录', en: 'Log in' },
  'auth.login.intro': {
    zh: '登录后可以管理已发布的故事，以及生成桌面端用的发布令牌。',
    en: 'Log in to manage published stories and create a publish token for the desktop app.',
  },
  'auth.email': { zh: '邮箱', en: 'Email' },
  'auth.password': { zh: '密码', en: 'Password' },
  'auth.password.new': { zh: '密码（至少 8 位）', en: 'Password (8+ characters)' },
  'auth.submit.signup': { zh: '创建账号', en: 'Create account' },
  'auth.submit.login': { zh: '登录', en: 'Log in' },
  'auth.busy': { zh: '请稍候...', en: 'Working...' },
  'auth.err.credentials': { zh: '邮箱或密码不对', en: 'Wrong email or password' },
  'auth.err.network': { zh: '网络不通，稍后再试一次', en: 'Network error, try again' },
  'auth.err.signedup': {
    zh: '账号建好了，但自动登录失败，去登录页试一次',
    en: 'Account created, but sign-in failed. Try the log in page.',
  },
  'auth.have': { zh: '已经有账号？', en: 'Already have an account? ' },
  'auth.havent': { zh: '还没有账号？', en: "Don't have an account? " },

  'beta.free.title': { zh: '公测期间免费', en: 'Free during beta' },
  'beta.free.signup': {
    zh: '现在注册的用户享受完整发布权限，不收费。',
    en: 'Sign up now and publishing is fully unlocked, at no cost.',
  },
  'beta.free.pricing.title': {
    zh: '现在是公测期，发布免费。',
    en: 'Publishing is free during the beta.',
  },
  'beta.free.pricing.body': {
    zh: '注册就能用，下面的价格等公测结束后才生效 —— 现在买的额度不会被消耗，会一直留到那时候。',
    en: 'Just sign up and use it. The prices below take effect after the beta — credits bought now are not consumed and stay with you until then.',
  },
  'beta.free.account': {
    zh: '公测期间免费，发布不限篇数',
    en: 'Free during beta — publish as many stories as you like',
  },

  'account.title': { zh: '账户', en: 'Account' },
  'account.credits': { zh: '可发布额度：', en: 'Publish credits: ' },
  'account.credits.unit': { zh: ' 篇', en: '' },
  'account.subscribed': {
    zh: '订阅中，一年内不限篇数',
    en: 'Subscribed — unlimited stories for a year',
  },
  'account.buy': { zh: '购买发布额度', en: 'Buy publish credits' },

  'pricing.title': { zh: '价格', en: 'Pricing' },
  'pricing.intro': {
    zh: 'App 免费使用：导入照片、还原路线、自动精选、本地预览，都不需要付费，也不需要注册。',
    en: 'The app is free: import photos, rebuild the route, auto-curate and preview locally — no payment, no account needed. ',
  },
  'pricing.intro.strong': {
    zh: '只有发布成公开链接时才收费。',
    en: 'You only pay to publish a public link.',
  },

  'story.selected': { zh: '选了 {n} 张', en: '{n} photos' },
  'story.overview': { zh: '行程全览', en: 'The whole trip' },
  'story.overview.sub': {
    zh: '{stops} 站 · {miles} 英里 · 点地图上的站可以跳到对应的照片',
    en: '{stops} stops · {miles} miles · tap a stop on the map to jump to its photos',
  },
  'share.label': { zh: '分享这段旅行', en: 'Share this trip' },
  'share.copy': { zh: '复制链接', en: 'Copy link' },
  'share.copied': { zh: '已复制', en: 'Copied' },
  'share.copy.manual': { zh: '复制下面的链接', en: 'Copy this link' },
  'share.wechat': { zh: '微信', en: 'WeChat' },
  'share.wechat.how': {
    zh: '用微信扫码打开，再转发给朋友或朋友圈',
    en: 'Scan with WeChat, then forward it from inside the app',
  },
  'share.close': { zh: '关闭', en: 'Close' },

  'story.days': { zh: '天', en: 'DAYS' },
  'story.stops': { zh: '站', en: 'STOPS' },
  'story.miles': { zh: '英里', en: 'MILES' },
  'story.photos': { zh: '张照片', en: 'PHOTOS' },
};

export function t(
  locale: Locale,
  key: keyof typeof dict | string,
  vars?: Record<string, string | number>,
) {
  const row = dict[key as string];
  let s = row ? row[locale] : (key as string);
  if (vars) {
    for (const [k, v] of Object.entries(vars)) {
      s = s.replaceAll(`{${k}}`, String(v));
    }
  }
  return s;
}
