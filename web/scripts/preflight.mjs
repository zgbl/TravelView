#!/usr/bin/env node
/**
 * 上线前自检。
 *
 * 缺一个环境变量的代价不是报错，而是**上线后才发现**:
 * webhook 静默失败、图片 404、OG 卡片没图。所以在部署前就查一遍。
 *
 *   node scripts/preflight.mjs
 */
const required = {
  DATABASE_URL: '数据库连接串',
  AUTH_SECRET: 'Auth.js 会话加密密钥（openssl rand -base64 32）',
  STRIPE_SECRET_KEY: 'Stripe 密钥',
  STRIPE_WEBHOOK_SECRET: 'Stripe webhook 签名密钥',
  NEXT_PUBLIC_MEDIA_BASE: '图片对外地址（本地磁盘就是 https://站点/media）',
  NEXT_PUBLIC_SITE_URL: '站点地址',
};

// 老的 R2_* 写法仍然认，别为了改名把已经跑着的部署弄挂
const alias = {
  S3_ACCESS_KEY_ID: 'R2_ACCESS_KEY_ID',
  S3_SECRET_ACCESS_KEY: 'R2_SECRET_ACCESS_KEY',
  S3_BUCKET: 'R2_BUCKET',
};
const has = (k) => {
  const v = process.env[k] ?? process.env[alias[k] ?? ''];
  return !!(v && v.trim());
};

const missing = [];
// 五档价格里至少要有一档能卖，否则定价页上一个能点的按钮都没有
const PRICE_KEYS = {
  STRIPE_PRICE_PRO_YEARLY: 'Pro 年付 $50 的 price ID',
  STRIPE_PRICE_PRO_MONTHLY: 'Pro 月付 $8 的 price ID',
  STRIPE_PRICE_CREDITS_5: '$5 = 1 篇额度的 price ID',
  STRIPE_PRICE_CREDITS_10: '$10 = 3 篇额度的 price ID',
  STRIPE_PRICE_CREDITS_25: '$25 = 10 篇额度的 price ID',
};
if (!Object.keys(PRICE_KEYS).some(has) &&
    !has('STRIPE_PRICE_ONETIME') && !has('STRIPE_PRICE_SUBSCRIPTION')) {
  missing.push(['STRIPE_PRICE_*', '一条价格 ID 都没配: ' +
    Object.entries(PRICE_KEYS).map(([k, v]) => `${k}(${v})`).join('、')]);
}
for (const [k, why] of Object.entries(required)) {
  if (!has(k)) missing.push([k, why]);
}
// 图片存哪，两套变量各查各的
const local = (process.env.STORAGE_DRIVER ?? 's3') === 'local';
if (local) {
  if (!has('MEDIA_ROOT')) {
    missing.push(['MEDIA_ROOT', '图片存放目录，必须在代码目录外面']);
  }
} else {
  for (const [k, why] of Object.entries({
    S3_ACCESS_KEY_ID: '对象存储 access key（R2 也可用 R2_ACCESS_KEY_ID）',
    S3_SECRET_ACCESS_KEY: '对象存储 secret key',
    S3_BUCKET: '存储桶名',
  })) {
    if (!has(k)) missing.push([k, why]);
  }
  if (!process.env.S3_ENDPOINT && !process.env.R2_ACCOUNT_ID) {
    missing.push(['S3_ENDPOINT', '对象存储的接入点（R2 可用 R2_ACCOUNT_ID 代替）']);
  }
}

const warn = [];
const site = process.env.NEXT_PUBLIC_SITE_URL ?? '';
if (site.includes('localhost')) {
  warn.push('NEXT_PUBLIC_SITE_URL 还是 localhost —— ' +
    'OG 卡片和发布回链会指到本机，别人打不开');
}
if ((process.env.NEXT_PUBLIC_MAP_TILES ?? '').includes('tile.openstreetmap.org')) {
  warn.push('地图瓦片还指着 OSM 公共服务器 —— ' +
    '正式流量会违反它的使用政策，见 Design/map-tiles.md');
}
if ((process.env.STRIPE_SECRET_KEY ?? '').startsWith('sk_test_')) {
  warn.push('Stripe 还是测试密钥，收不到真钱');
}
if (local && (process.env.MEDIA_ROOT ?? '').includes('/web')) {
  warn.push('MEDIA_ROOT 看着在代码目录里 —— 下次部署会被整个覆盖掉');
}

for (const w of warn) console.log(`  ⚠︎  ${w}`);
if (missing.length) {
  console.log('\n缺少这些环境变量:');
  for (const [k, why] of missing) console.log(`  ✗  ${k.padEnd(24)} ${why}`);
  process.exit(1);
}
console.log(`\n✓ ${Object.keys(required).length} 个必需变量都在`);
