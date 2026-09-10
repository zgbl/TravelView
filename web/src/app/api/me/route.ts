import { NextResponse } from 'next/server';
import { z } from 'zod';
import { requireUserOrToken } from '@/lib/auth';
import { one } from '@/lib/db';

export const dynamic = 'force-dynamic';

/**
 * 我是谁。
 *
 * **手机端必须有这个接口。** 之前 App 只拿着一个发布令牌，
 * 从来没问过服务器"这个令牌是谁的" —— 用户在个人中心里看不到
 * 自己的邮箱、昵称、主页地址，连自己登的是哪个账号都不知道。
 *
 * 网页走 cookie、App 走 Bearer 令牌，两边都认。
 */
export async function GET(req: Request) {
  const user = await requireUserOrToken(req);
  if (!user) return NextResponse.json({ error: '未登录' }, { status: 401 });

  const row = await one<{
    email: string;
    name: string | null;
    handle: string | null;
    story_credits: number;
    subscription_status: string | null;
    created_at: string;
  }>(`select email, name, handle, coalesce(story_credits, 0) as story_credits,
             subscription_status, created_at
        from users where id = $1`, [user.id]);
  if (!row) return NextResponse.json({ error: '找不到账号' }, { status: 404 });

  const site = (process.env.NEXT_PUBLIC_SITE_URL ?? '').replace(/\/+$/, '');
  return NextResponse.json({
    email: row.email,
    name: row.name,
    handle: row.handle,
    // 有 handle 才有公开主页。没有的话让客户端引导用户去设一个，
    // 而不是给一个点开是 404 的链接
    homeUrl: row.handle ? `${site}/u/${row.handle}` : null,
    credits: row.story_credits,
    subscribed: row.subscription_status === 'active',
    since: row.created_at,
  });
}

/** 用户改自己的资料：显示名和公开主页地址。 */
const RESERVED = new Set([
  'admin', 'api', 'about', 'account', 'billing', 'help', 'login', 'logout',
  'signup', 'pricing', 'stories', 'story', 'support', 'settings', 'link',
  'u', 's', 'www', 'mail', 'root', 'null', 'undefined', 'me', 'new',
]);

const Body = z.object({
  name: z.string().trim().max(40).optional(),
  handle: z.string().trim().toLowerCase()
    .regex(/^[a-z0-9_]{3,20}$/, 'BAD_HANDLE').optional(),
});

export async function PATCH(req: Request) {
  const user = await requireUserOrToken(req);
  if (!user) return NextResponse.json({ error: '未登录' }, { status: 401 });

  const parsed = Body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    const bad = parsed.error.issues[0]?.message;
    return NextResponse.json(
      { error: bad === 'BAD_HANDLE' ? 'BAD_HANDLE' : '名字太长了' },
      { status: 400 },
    );
  }

  if (parsed.data.name !== undefined) {
    // 空字符串存 null，别在库里留一堆空串
    await one('update users set name = $2 where id = $1',
      [user.id, parsed.data.name || null]);
  }

  const handle = parsed.data.handle;
  if (handle !== undefined) {
    if (RESERVED.has(handle)) {
      return NextResponse.json({ error: 'TAKEN' }, { status: 409 });
    }
    try {
      await one('update users set handle = $2 where id = $1',
        [user.id, handle]);
    } catch {
      // 唯一索引撞了 —— 这是唯一可能的失败，不用去猜别的原因
      return NextResponse.json({ error: 'TAKEN' }, { status: 409 });
    }
  }

  return NextResponse.json({ ok: true });
}
