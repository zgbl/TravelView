import { createHash, randomBytes } from 'node:crypto';
import { NextResponse } from 'next/server';
import { z } from 'zod';
import { one, query } from '@/lib/db';
import { mailConfigured, resetMail, sendMail } from '@/lib/mail';

export const dynamic = 'force-dynamic';

const Body = z.object({
  email: z.string().email(),
  // 信里的链接用哪种语言。桌面端/手机端按自己的界面语言传
  locale: z.enum(['zh', 'en']).optional(),
});

/** 链接有效期。够用户去邮箱点一下，又不至于在收件箱里躺一整天。 */
const TTL_MINUTES = 60;

/**
 * 「忘记密码」第一步：发一封带一次性链接的信。
 *
 * **不管邮箱存不存在，返回的都是同一句话。**
 * 如果"这个邮箱没注册过"和"信已发出"是两种回复，任何人都可以拿这个接口
 * 逐个试探谁在这里注册过 —— 那是在替别人泄露隐私。
 *
 * 网页、桌面端、手机端**共用这一个接口**。三端各自实现一遍重置逻辑，
 * 迟早会有一端的校验比别人松，而最松的那一端就是整个系统的安全水位。
 */
export async function POST(req: Request) {
  const parsed = Body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: '邮箱格式不对' }, { status: 400 });
  }
  const email = parsed.data.email.trim().toLowerCase();
  const locale = parsed.data.locale ?? 'zh';

  // 没配 SMTP 就如实说，不要假装发出去了 —— 用户会一直等一封永远不来的信
  if (!mailConfigured) {
    return NextResponse.json(
      { error: '这台服务器还没配置发信（SMTP）' }, { status: 503 });
  }

  const user = await one<{ id: string; email: string }>(
    'select id, email from users where email = $1', [email]);

  if (user) {
    // 同一个人反复点，旧链接立刻作废 —— 邮箱里永远只有最后一封是活的
    await query(
      `update password_resets set used_at = now()
        where user_id = $1 and used_at is null`, [user.id]);

    const token = randomBytes(32).toString('base64url');
    const hash = createHash('sha256').update(token).digest('hex');
    const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? null;

    await query(
      `insert into password_resets (user_id, token_hash, expires_at, requested_ip)
       values ($1, $2, now() + ($3 || ' minutes')::interval, $4)`,
      [user.id, hash, String(TTL_MINUTES), ip],
    );

    const base = (process.env.NEXT_PUBLIC_SITE_URL ?? '').replace(/\/$/, '');
    const link = `${base}/${locale}/reset?token=${token}`;
    const mail = resetMail(link, locale);
    try {
      await sendMail({ to: user.email, ...mail });
    } catch (e) {
      // 发信挂了要让用户知道，否则他会一直刷新邮箱
      console.error('[forgot] 发信失败', e);
      return NextResponse.json({ error: '发信失败，稍后再试' }, { status: 502 });
    }
  }

  return NextResponse.json({ ok: true });
}
