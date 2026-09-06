import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/lib/admin';
import { betaState } from '@/lib/access';
import { stripeStatus } from '@/lib/stripe';
import { query, one } from '@/lib/db';
import DailyBars from '@/components/DailyBars';

export const dynamic = 'force-dynamic';

/**
 * 站长后台。
 *
 * 只回答三个问题:
 *   1. 有多少人注册了（离 100 人还差多远 —— 到了就该开始收费）
 *   2. 有没有人真的发布
 *   3. 发出去的东西有没有人看
 *
 * **不做通用分析平台。** 现在需要的是几个数字告诉你该不该收费，
 * 不是一堆看着热闹但改变不了任何决定的图表。
 */
const DAYS = 30;

function series(rows: { day: string; n: number }[], days = DAYS) {
  const byDay = new Map(rows.map((r) => [r.day, r.n]));
  const out: { day: string; n: number }[] = [];
  const today = new Date();
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(today);
    d.setDate(today.getDate() - i);
    const key = d.toISOString().slice(0, 10);
    out.push({ day: key, n: byDay.get(key) ?? 0 });
  }
  return out;
}

export default async function Admin() {
  const admin = await requireAdmin();
  // 不是管理员就当这个页面不存在 —— 403 等于告诉别人这里有东西
  if (!admin) notFound();

  const beta = await betaState();
  const stripe = stripeStatus();

  const [totals] = await query<{
    users: string; stories: string; photos: string;
    views: string; paying: string; tokens: string;
  }>(`select
        (select count(*) from users)::text as users,
        (select count(*) from stories)::text as stories,
        (select coalesce(sum(photo_count),0) from stories)::text as photos,
        (select coalesce(sum(view_count),0) from stories)::text as views,
        (select count(*) from users
          where story_credits > 0 or subscription_status = 'active')::text
          as paying,
        (select count(*) from publish_tokens where revoked_at is null)::text
          as tokens`);

  const signups = series(await query<{ day: string; n: number }>(
    `select to_char(created_at::date,'YYYY-MM-DD') as day, count(*)::int as n
       from users where created_at > now() - interval '${DAYS} days'
      group by 1`));

  const views = series(await query<{ day: string; n: number }>(
    `select to_char(day,'YYYY-MM-DD') as day, sum(count)::int as n
       from view_daily where day > current_date - ${DAYS}
      group by 1`));

  const published = series(await query<{ day: string; n: number }>(
    `select to_char(created_at::date,'YYYY-MM-DD') as day, count(*)::int as n
       from stories where created_at > now() - interval '${DAYS} days'
      group by 1`));

  const recent = await query<{
    email: string; created_at: string; stories: string;
  }>(`select u.email, u.created_at,
             (select count(*) from stories s where s.user_id = u.id)::text
               as stories
        from users u order by u.created_at desc limit 12`);

  const top = await query<{
    slug: string; title: string; view_count: string; email: string;
  }>(`select s.slug, s.title, s.view_count::text, u.email
        from stories s join users u on u.id = s.user_id
       order by s.view_count desc limit 8`);

  const pct = Math.min(100, Math.round((beta.users / beta.limit) * 100));

  return (
    <main className="mx-auto max-w-5xl px-6 py-14">
      <div className="mb-10 flex items-center justify-between">
        <h1 className="text-3xl font-semibold tracking-tight">后台</h1>
        <div className="flex gap-4 text-sm">
          <Link href="/admin/users" className="text-muted hover:text-paper">
            用户管理
          </Link>
          <Link href="/stories" className="text-muted hover:text-paper">
            我的故事
          </Link>
        </div>
      </div>

      {/* 唯一真正要盯的数字: 离开始收费还差多少人 */}
      <section className="rounded-2xl border border-accentBright/30
        bg-accentBright/5 p-6">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <div>
            <span className="text-4xl font-semibold">{beta.users}</span>
            <span className="ml-2 text-muted">/ {beta.limit} 位注册用户</span>
          </div>
          <div className="text-sm">
            {beta.free ? (
              <span className="text-accentBright">
                公测中，所有人按付费用户对待 &middot; 还差 {beta.remaining} 人
              </span>
            ) : (
              <span>已达上限，正在按额度收费</span>
            )}
          </div>
        </div>
        <div className="mt-4 h-1.5 w-full overflow-hidden rounded-full bg-white/10">
          <div className="h-full rounded-full bg-accentBright"
            style={{ width: `${pct}%` }} />
        </div>
        <p className="mt-3 text-xs text-muted">
          到 {beta.limit} 人自动转为收费。想提前或推迟，改服务器上的
          <code className="mx-1">FREE_BETA</code>（on / off / auto）后重启。
        </p>
      </section>

      {/* 支付接通状态。密钥不在这里填 —— 见下面那行说明 */}
      <section className="mt-6 rounded-2xl border border-white/12 p-6">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-medium">支付（Stripe）</h2>
          <span className={`text-xs ${stripe.ready
            ? 'text-accentBright' : 'text-muted'}`}>
            {stripe.ready
              ? (stripe.livemode ? '已接通（正式模式）' : '已接通（测试模式）')
              : '还没接通'}
          </span>
        </div>
        <div className="mt-4 grid gap-2 text-sm sm:grid-cols-2">
          <Check ok={stripe.secretKey} k="STRIPE_SECRET_KEY" />
          <Check ok={stripe.webhookSecret} k="STRIPE_WEBHOOK_SECRET" />
          <Check ok={stripe.priceProYearly} k="STRIPE_PRICE_PRO_YEARLY（$50/年）" />
          <Check ok={stripe.priceProMonthly} k="STRIPE_PRICE_PRO_MONTHLY（$8/月）" />
          <Check ok={stripe.priceCredits5usd} k="STRIPE_PRICE_CREDITS_5（$5 = 2 篇）" />
          <Check ok={stripe.priceCredits10usd} k="STRIPE_PRICE_CREDITS_10（$10 = 5 篇）" />
          <Check ok={stripe.priceCredits25usd} k="STRIPE_PRICE_CREDITS_25（$25 = 15 篇）" />
        </div>
        <p className="mt-4 text-xs leading-relaxed text-muted">
          密钥写在服务器的 <code>/etc/travelview/env</code>，改完
          <code className="mx-1">sudo systemctl restart travelview-web</code>。
          <strong className="text-paper/80">
            后台刻意不提供填密钥的表单
          </strong>
          —— 能读写支付密钥的网页本身就是最值钱的攻击目标，
          而且密钥一旦进了数据库，备份、日志、截图里到处都是它。
        </p>
      </section>

      <section className="mt-8 grid grid-cols-2 gap-3 md:grid-cols-3">
        <Stat n={totals.users} k="注册用户" />
        <Stat n={totals.stories} k="已发布 Story" />
        <Stat n={totals.views} k="累计浏览" />
        <Stat n={totals.photos} k="服务器上的照片" />
        <Stat n={totals.tokens} k="有效发布令牌" />
        <Stat n={totals.paying} k="有付费权益的人" />
      </section>

      <section className="mt-10 grid gap-8 md:grid-cols-2">
        <div className="rounded-2xl border border-white/12 p-5">
          <DailyBars data={signups} label="每日注册" />
        </div>
        <div className="rounded-2xl border border-white/12 p-5">
          <DailyBars data={views} label="每日浏览" color="#7aa2f7" />
        </div>
        <div className="rounded-2xl border border-white/12 p-5 md:col-span-2">
          <DailyBars data={published} label="每日发布" color="#e0a458" />
        </div>
      </section>

      <section className="mt-12 grid gap-8 md:grid-cols-2">
        <div>
          <h2 className="mb-3 text-sm font-medium text-muted">最近注册</h2>
          <table className="w-full text-sm">
            <tbody>
              {recent.map((r) => (
                <tr key={r.email} className="border-t border-white/8">
                  <td className="py-2">{r.email}</td>
                  <td className="py-2 text-right text-muted">
                    {r.stories} 篇
                  </td>
                  <td className="py-2 pl-3 text-right text-xs text-muted">
                    {r.created_at.toString().slice(0, 10)}
                  </td>
                </tr>
              ))}
              {recent.length === 0 && (
                <tr><td className="py-3 text-muted">还没有人注册</td></tr>
              )}
            </tbody>
          </table>
        </div>

        <div>
          <h2 className="mb-3 text-sm font-medium text-muted">最多人看的 Story</h2>
          <table className="w-full text-sm">
            <tbody>
              {top.map((r) => (
                <tr key={r.slug} className="border-t border-white/8">
                  <td className="py-2">
                    <Link href={`/s/${r.slug}`} className="hover:text-accentBright">
                      {r.title}
                    </Link>
                    <div className="text-xs text-muted">{r.email}</div>
                  </td>
                  <td className="py-2 text-right">{r.view_count}</td>
                </tr>
              ))}
              {top.length === 0 && (
                <tr><td className="py-3 text-muted">还没有人发布</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </section>

      <p className="mt-14 text-xs text-muted">
        浏览统计只按天计数，**不记录任何访客身份** ——
        不存 IP、不下 cookie、不做指纹。
      </p>
    </main>
  );
}

function Check({ ok, k }: { ok: boolean; k: string }) {
  return (
    <div className="flex items-center gap-2">
      <span className={ok ? 'text-accentBright' : 'text-muted'}>
        {ok ? '\u2713' : '\u2014'}
      </span>
      <code className="text-xs text-muted">{k}</code>
    </div>
  );
}

function Stat({ n, k }: { n: string; k: string }) {
  return (
    <div className="rounded-2xl border border-white/12 px-5 py-4">
      <div className="text-2xl font-semibold">{n}</div>
      <div className="mt-1 text-xs text-muted">{k}</div>
    </div>
  );
}
