#!/usr/bin/env node
/**
 * 把 Stripe 上已经付过的钱同步到数据库。
 *
 * 什么时候用: webhook 当时没配好 / 服务当时没起 / 沙盒里手动付的测试单 ——
 * 钱收到了但用户的额度没加。跑一次这个脚本补上。
 *
 * 幂等: 和线上同一套闸门（stripe_events + payments.stripe_session_id 唯一），
 * 重复跑不会重复发放。
 *
 *   node scripts/sync-stripe.mjs            # 只看会发生什么，不写库
 *   node scripts/sync-stripe.mjs --apply    # 真的写
 *
 * 环境变量从 /etc/travelview/env 读，跑之前 `set -a; . /etc/travelview/env; set +a`
 */
import Stripe from 'stripe';
import pg from 'pg';

const APPLY = process.argv.includes('--apply');
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY ?? '');
const db = new pg.Pool({
  connectionString: process.env.TRAVELVIEW_DATABASE_URL,
  ssl: process.env.TRAVELVIEW_DATABASE_URL?.includes('sslmode=disable')
    ? undefined : { rejectUnauthorized: false },
});

// 和 src/lib/stripe.ts 保持一致。改了那边记得改这里。
const CREDITS = {
  [process.env.STRIPE_PRICE_CREDITS_5 ?? 'x']: 2,
  [process.env.STRIPE_PRICE_CREDITS_10 ?? 'y']: 5,
  [process.env.STRIPE_PRICE_CREDITS_25 ?? 'z']: 15,
};
const SUBS = {
  [process.env.STRIPE_PRICE_PRO_YEARLY ?? 'x']: '1 year',
  [process.env.STRIPE_PRICE_PRO_MONTHLY ?? 'y']: '1 month',
};

const q = (sql, params = []) => db.query(sql, params).then((r) => r.rows);

async function findUser(session) {
  // 三条线索都试: client_reference_id -> metadata -> customer -> 邮箱
  const id = session.client_reference_id ?? session.metadata?.userId;
  if (id) {
    const [u] = await q('select id, email from users where id = $1', [id]);
    if (u) return u;
  }
  const cust = typeof session.customer === 'string' ? session.customer : null;
  if (cust) {
    const [u] = await q(
      'select id, email from users where stripe_customer_id = $1', [cust]);
    if (u) return u;
  }
  const email = session.customer_details?.email ?? session.customer_email;
  if (email) {
    const [u] = await q(
      'select id, email from users where lower(email) = lower($1)', [email]);
    if (u) {
      // 顺手把 customer id 补上，以后订阅事件才认得出他
      if (cust && APPLY) {
        await q('update users set stripe_customer_id = $2 where id = $1',
          [u.id, cust]).catch(() => {});
      }
      return u;
    }
  }
  return null;
}

const sessions = await stripe.checkout.sessions.list({
  limit: 100, expand: ['data.line_items'],
});

let done = 0;
for (const s of sessions.data) {
  if (s.payment_status !== 'paid' && s.status !== 'complete') continue;

  const user = await findUser(s);
  if (!user) {
    console.log(`跳过 ${s.id}: 找不到对应用户`,
      s.customer_details?.email ?? '');
    continue;
  }

  const priceId = s.line_items?.data?.[0]?.price?.id;
  const credits = CREDITS[priceId] ?? 0;
  const span = SUBS[priceId];
  if (!credits && !span) {
    console.log(`跳过 ${s.id}: 认不出的 price ${priceId}`);
    continue;
  }

  const key = `session:${s.id}`;
  const [seen] = await q('select id from stripe_events where id = $1', [key]);
  const [paid] = await q(
    'select id from payments where stripe_session_id = $1', [s.id]);
  if (seen || paid) {
    console.log(`已处理过 ${s.id}（${user.email}）`);
    continue;
  }

  const what = span ? `订阅 ${span}` : `+${credits} 篇`;
  console.log(`${APPLY ? '发放' : '将发放'} ${s.id} -> ${user.email}: ${what}`);
  if (!APPLY) { done++; continue; }

  await q(`insert into stripe_events (id, type) values ($1, $2)
           on conflict (id) do nothing`, [key, 'checkout.session.synced']);
  if (span) {
    await q(`update users set subscription_status = 'active',
               subscription_until = now() + $2::interval where id = $1`,
      [user.id, span]);
  } else {
    await q('update users set story_credits = story_credits + $2 where id = $1',
      [user.id, credits]);
  }
  const row = [user.id, s.id, String(s.payment_intent ?? ''),
    span ? 'pro' : `credits_${credits}`, s.amount_total, s.currency, 'paid'];
  await q(`insert into payments
             (user_id, stripe_session_id, stripe_payment_intent, kind,
              amount_cents, currency, status, credits_granted)
           values ($1,$2,$3,$4,$5,$6,$7,$8)
           on conflict (stripe_session_id) do nothing`, [...row, credits])
    .catch(() => q(`insert into payments
             (user_id, stripe_session_id, stripe_payment_intent, kind,
              amount_cents, currency, status)
           values ($1,$2,$3,$4,$5,$6,$7)
           on conflict (stripe_session_id) do nothing`, row));
  done++;
}

console.log(APPLY ? `完成，处理了 ${done} 笔` :
  `预演完毕，有 ${done} 笔待处理。加 --apply 才会真的写库。`);
await db.end();
