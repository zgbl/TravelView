import { NextResponse } from 'next/server';
import { z } from 'zod';
import { one } from '@/lib/db';
import { betaState, entitlementOf } from '@/lib/access';
import { isLocal, localPathFor } from '@/lib/storage';
import { stat } from 'fs/promises';
import type { Story } from '@/lib/story';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * 发布的第二段: 图全部传完了，把这一篇正式上线。
 *
 * **额度在这里扣，不在建 Story 的时候扣。**
 * 一次发布上百张图，家用上行断一次是常态；在开始传的时候就扣，
 * 断了就等于用户付了钱却什么都没拿到。钱只在东西真的交付之后收。
 *
 * 幂等: `credit_consumed` 保证续传、重试、重复调用都只扣一次。
 */
const Body = z.object({ storyId: z.string().uuid() });

export async function POST(req: Request) {
  const token = (req.headers.get('authorization') ?? '')
    .replace(/^Bearer\s+/i, '').trim();
  if (!token) return NextResponse.json({ error: '缺少发布令牌' }, { status: 401 });

  const owner = await one<{ user_id: string }>(
    `select user_id from publish_tokens
      where token = $1 and revoked_at is null`, [token]);
  if (!owner) return NextResponse.json({ error: '令牌无效' }, { status: 401 });

  const parsed = Body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: '参数不对' }, { status: 400 });
  }

  const story = await one<{
    id: string; slug: string; media_prefix: string | null;
    manifest: Story; published_at: string | null; credit_consumed: boolean;
  }>(`select id, slug, media_prefix, manifest, published_at,
             coalesce(credit_consumed, false) as credit_consumed
        from stories where id = $1 and user_id = $2`,
    [parsed.data.storyId, owner.user_id]);
  if (!story) return NextResponse.json({ error: '找不到这一篇' }, { status: 404 });

  // 本地磁盘驱动下真的去数一遍文件。少一张就不算发布完成 ——
  // 上线一篇图裂的游记，比让用户再点一次重试糟糕得多
  const prefix = story.media_prefix ?? `s/${story.slug}`;
  if (isLocal) {
    const want = [
      ...story.manifest.photos.map((p) => p.web.path),
      ...story.manifest.photos.filter((p) => p.thumb).map((p) => p.thumb!),
    ];
    const missing: string[] = [];
    for (const rel of want) {
      try {
        await stat(localPathFor(`${prefix}/${rel}`));
      } catch {
        missing.push(rel);
        if (missing.length >= 5) break;
      }
    }
    if (missing.length) {
      return NextResponse.json(
        { error: 'INCOMPLETE', missing, message: '还有照片没传完' },
        { status: 409 });
    }
  }

  // 额度只扣一次。续传、重试、手滑点两下都不该再扣
  let consumed = false;
  if (!story.credit_consumed) {
    const user = await one<{
      story_credits: number;
      subscription_status: string | null;
      subscription_until: string | null;
    }>(`select story_credits, subscription_status, subscription_until
          from users where id = $1`, [owner.user_id]);
    const ent = entitlementOf(user ?? null, await betaState());
    if (!ent.allowed) {
      return NextResponse.json(
        { error: 'NEED_PAYMENT', message: '还没有可用的发布额度' },
        { status: 402 });
    }
    if (ent.consumesCredit) {
      await one(
        'update users set story_credits = story_credits - 1 where id = $1',
        [owner.user_id]);
      consumed = true;
    }
    await one(
      'update stories set credit_consumed = true where id = $1', [story.id]);
  }

  await one(
    `update stories set published_at = coalesce(published_at, now()),
            updated_at = now() where id = $1`, [story.id]);

  return NextResponse.json({ ok: true, slug: story.slug, consumed });
}
