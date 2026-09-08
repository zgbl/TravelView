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
  'auth.name': { zh: '显示名（可选，之后能改）', en: 'Display name (optional)' },
  'account.name': { zh: '显示名', en: 'Display name' },
  'account.name.hint': {
    zh: '会显示在你发布的故事上。留空就只显示邮箱前缀。',
    en: 'Shown on the stories you publish. Left empty, only your email prefix is used.',
  },
  'account.save': { zh: '保存', en: 'Save' },
  'account.saved': { zh: '已保存', en: 'Saved' },
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

  // ── 订阅与额度（/account/billing）──
  'account.beta.credits.kept': {
    zh: '（你买的 {n} 篇额度留着，公测期不会消耗）',
    en: ' (your {n} purchased credits are kept — the beta does not consume them)',
  },
  'account.delete.title': { zh: '删除账户', en: 'Delete account' },
  'account.delete.body': {
    zh: '会删除你的全部故事和服务器上的图片。你电脑上的原图不受影响。需要请发邮件联系我们。',
    en: 'This removes all your stories and the images on our server. The originals on your computer are untouched. Email us if you want this done.',
  },
  'pricing.pro.f1': { zh: '一年内发布任意多篇', en: 'Publish as many stories as you like' },
  'pricing.pro.f2': {
    zh: '永久有效的公开地址，随时可更新',
    en: 'A permanent public link you can update anytime',
  },
  'pricing.pro.f3': { zh: '社交平台分享预览图', en: 'Social share preview images' },
  'pricing.pro.f4': {
    zh: '退订后已发布的内容不受影响',
    en: 'Cancel anytime — published stories stay up',
  },
  'pricing.packs.from': { zh: ' 起', en: '+' },
  'pricing.packs.sub': {
    zh: '不想订阅就买额度，买了不过期',
    en: "Don't want a subscription? Buy credits — they never expire",
  },
  'pricing.packs.f4': {
    zh: '额度不过期，和订阅可以并存',
    en: 'Credits never expire and work alongside a subscription',
  },
  'billing.paid': {
    zh: '付款成功，权益已经加到你的账户上了。',
    en: 'Payment received — your account has been updated.',
  },
  'plan.pro_yearly.price': { zh: '$50 / 年', en: '$50 / year' },
  'plan.pro_monthly.price': { zh: '$8 / 月', en: '$8 / month' },
  'plan.credits_2.price': { zh: '$5', en: '$5' },
  'plan.credits_5.price': { zh: '$10', en: '$10' },
  'plan.credits_15.price': { zh: '$25', en: '$25' },
  'billing.history.empty': {
    zh: '还没有付款记录。在这里付的每一笔都会列在这一栏，不用去 Stripe 查。',
    en: "No payments yet. Everything you pay for here will be listed in this table — you won't have to look it up in Stripe.",
  },
  // ── 桌面端连接 ──
  'link.title': { zh: '连接桌面端', en: 'Connect your desktop app' },
  'link.intro': {
    zh: '打开桌面端的「连接账号」，把它显示的那串码敲在这里。',
    en: 'Open “Connect account” in the desktop app and type the code it shows here.',
  },
  'link.placeholder': { zh: '例如 KDR8-Q2M7', en: 'e.g. KDR8-Q2M7' },
  'link.submit': { zh: '确认这台设备', en: 'Approve this device' },
  'link.busy': { zh: '正在确认...', en: 'Approving...' },
  'link.done': {
    zh: '连上了。回到桌面端，它几秒内就会自己登录。',
    en: 'Connected. Go back to the desktop app — it will sign in within a few seconds.',
  },
  'link.note': {
    zh: '这串码 15 分钟内有效，只能用一次。发布令牌由服务器直接发给那台机器，不经过你的剪贴板。随时可以在账户页吊销。',
    en: 'The code is valid for 15 minutes and can be used once. The publish token goes straight to that machine — it never passes through your clipboard. You can revoke it any time from your account.',
  },

  // ── 公开主页 ──
  'profile.stories': { zh: '{n} 篇故事', en: '{n} stories' },
  'profile.empty': {
    zh: '还没有公开的故事。',
    en: 'No public stories yet.',
  },
  'profile.own.cta': {
    zh: '这是你的公开主页。把这个地址分享出去，别人看到的就是这一页。',
    en: 'This is your public page. Share this link — this is what people will see.',
  },
  'profile.made': {
    zh: '用 TravelView 制作', en: 'Made with TravelView',
  },
  'profile.handle': { zh: '主页地址', en: 'Public page' },
  'profile.handle.save': { zh: '设置', en: 'Save' },
  'profile.handle.saved': { zh: '已设置', en: 'Saved' },
  'profile.handle.open': { zh: '打开我的主页', en: 'Open my page' },
  'link.entry': { zh: '连接桌面端', en: 'Connect desktop app' },
  'profile.handle.hint': {
    zh: '3-20 位，只能用小写字母、数字和下划线。设置后你的主页就是 /u/你的名字。',
    en: '3-20 characters, lowercase letters, numbers and underscore. Your page will be /u/yourname.',
  },
  'profile.handle.taken': { zh: '这个名字被占了', en: 'That name is taken' },
  'profile.handle.bad': {
    zh: '只能用 3-20 位小写字母、数字和下划线',
    en: 'Use 3-20 lowercase letters, numbers or underscore',
  },

  'story.madewith': {
    zh: '用 TravelView 制作你自己的',
    en: 'Make your own with TravelView',
  },
  'player.open': { zh: '全屏播放', en: 'Play fullscreen' },
  'player.hint': {
    zh: '像放幻灯片一样看完这趟旅行',
    en: 'Watch the whole trip play out',
  },
  'player.end': { zh: '播放结束', en: 'The end' },
  'player.again': { zh: '再看一遍', en: 'Play again' },
  'player.play': { zh: '播放', en: 'Play' },
  'player.pause': { zh: '暂停', en: 'Pause' },
  'player.exit': { zh: '退出播放', en: 'Exit' },
  'player.fromHere': { zh: '从这里播放', en: 'Play from here' },
  'player.fromStop': { zh: '第 {n} 站起', en: 'from stop {n}' },
  'player.volume': { zh: '音量', en: 'Volume' },
  'player.full': { zh: '全屏 (F)', en: 'Fullscreen (F)' },
  'player.windowed': { zh: '退出全屏 (F)', en: 'Exit fullscreen (F)' },
  'player.unmute': { zh: '打开配乐', en: 'Play music' },
  'player.mute': { zh: '关掉配乐', en: 'Mute music' },
  'billing.title': { zh: '订阅与额度', en: 'Plan & credits' },
  'billing.back': { zh: '返回账户', en: 'Back to account' },
  'billing.manage': { zh: '管理订阅', en: 'Manage plan' },
  'billing.entry': { zh: '订阅与额度', en: 'Plan & credits' },
  'billing.portal': {
    zh: '管理订阅 / 换卡 / 收据',
    en: 'Manage subscription & payment method',
  },
  'billing.portal.busy': { zh: '正在打开...', en: 'Opening...' },
  'billing.portal.err': {
    zh: '暂时打不开，请稍后再试',
    en: "Couldn't open it just now — please try again",
  },
  'billing.subscribed': {
    zh: 'Pro 订阅中，不限篇数',
    en: 'Pro — unlimited stories',
  },
  'billing.renews': { zh: '下次续费 {date}', en: 'renews {date}' },
  'billing.credits': { zh: '可发布额度：', en: 'Publish credits: ' },
  'billing.credits.unit': { zh: ' 篇', en: '' },
  'billing.pastdue': {
    zh: '上次扣款没成功（多半是卡过期）。权益到期前还能用，去下面的「管理订阅」换张卡就行。',
    en: 'Your last payment failed (usually an expired card). Access continues until the period ends — open “Manage plan” below to update your card.',
  },
  'billing.beta.title': { zh: '公测期发布免费', en: 'Publishing is free during the beta' },
  'billing.beta.body': {
    zh: '，现在发布不扣额度。你买的额度会一直留着，公测结束（注册满 {limit} 人）后才开始消耗。',
    en: ' — publishing costs no credits right now. Credits you buy stay untouched and only start being used once the beta ends (at {limit} sign-ups).',
  },
  'billing.choose': { zh: '选一个方案', en: 'Choose a plan' },
  'billing.topup': { zh: '加买额度', en: 'Add more credits' },
  'billing.choose.sub': {
    zh: 'Pro 订阅不限篇数；不想订阅就按篇买，额度不过期，和订阅可以并存。',
    en: 'Pro is unlimited. Prefer not to subscribe? Buy credits per story — they never expire and work alongside a subscription.',
  },
  'billing.pro.title': { zh: 'Pro · 不限篇数', en: 'Pro · unlimited' },
  'billing.pro.per.year': { zh: ' / 年', en: ' / year' },
  'billing.pro.alt': { zh: '或 $8 / 月，随时取消', en: 'or $8 / month, cancel anytime' },
  'billing.packs.title': { zh: '额度包 · 按篇买', en: 'Credit packs · pay per story' },
  'billing.packs.5': { zh: '$5 = 2 篇（$2.5 一篇）', en: '$5 = 2 stories ($2.50 each)' },
  'billing.packs.10': { zh: '$10 = 5 篇（$2 一篇）', en: '$10 = 5 stories ($2.00 each)' },
  'billing.packs.25': { zh: '$25 = 15 篇（$1.67 一篇）', en: '$25 = 15 stories ($1.67 each)' },
  'billing.notready': {
    zh: '支付还没开通，公测期间发布本来就是免费的。',
    en: 'Payments are not live yet — publishing is free during the beta anyway.',
  },
  'billing.testmode': {
    zh: '当前是 Stripe 测试模式，不会真的扣款。测试卡号 4242 4242 4242 4242，有效期填未来任意日期，CVC 任意三位。',
    en: 'Stripe is in test mode — no real charge. Test card 4242 4242 4242 4242, any future expiry, any 3-digit CVC.',
  },
  'billing.history': { zh: '付款记录', en: 'Payment history' },
  // 只说这个按钮实际能做什么。**不要提退款** ——
  // 我们没有承诺过退款政策，客户门户默认也不给用户自助退款，
  // 写上去等于凭空立下一个我们没打算兑现的承诺
  'billing.history.note': {
    zh: '换卡、取消订阅在「管理订阅」里操作。',
    en: 'Update your card or cancel a subscription under “Manage subscription”.',
  },
  'billing.granted': { zh: '+{n} 篇', en: '+{n} stories' },
  'billing.privacy': {
    zh: '无论哪一档，原图都不会上传。服务器上只有你挑中的那些照片的压缩版本。',
    en: 'On every plan, your original photos stay on your computer. The server only holds compressed copies of the photos you picked.',
  },
  'billing.link.signedin': { zh: '已经注册了？', en: 'Already have an account? ' },
  'billing.link.go': {
    zh: '去「订阅与额度」查看当前权益并付款',
    en: 'Open Plan & credits to see your access and pay',
  },
  'checkout.busy': { zh: '正在跳转...', en: 'Redirecting...' },
  'checkout.err': {
    zh: '暂时无法发起支付，请稍后再试',
    en: "Couldn't start checkout — please try again",
  },

  // 档位名。价格数字不翻译，文字要翻译
  'plan.pro_yearly.name': { zh: 'Pro · 年付', en: 'Pro · yearly' },
  'plan.pro_yearly.blurb': {
    zh: '不限篇数，平均 $4.17/月', en: 'Unlimited, $4.17/mo equivalent' },
  'plan.pro_monthly.name': { zh: 'Pro · 月付', en: 'Pro · monthly' },
  'plan.pro_monthly.blurb': {
    zh: '不限篇数，随时取消', en: 'Unlimited, cancel anytime' },
  'plan.credits_2.name': { zh: '2 篇额度', en: '2 credits' },
  'plan.credits_2.blurb': { zh: '$2.5 一篇，先试试', en: '$2.50 each — try it out' },
  'plan.credits_5.name': { zh: '5 篇额度', en: '5 credits' },
  'plan.credits_5.blurb': { zh: '$2 一篇', en: '$2.00 each' },
  'plan.credits_15.name': { zh: '15 篇额度', en: '15 credits' },
  'plan.credits_15.blurb': { zh: '$1.67 一篇，最划算', en: '$1.67 each — best value' },

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
    zh: '{stops} 站 · {dist} {unit} · 点地图上的站可以跳到对应的照片',
    en: '{stops} stops · {dist} {unit} · tap a stop on the map to jump to its photos',
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
