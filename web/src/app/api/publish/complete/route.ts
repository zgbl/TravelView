import { NextResponse } from 'next/server';
import { z } from 'zod';
import { one } from '@/lib/db';
import {
  FREE_UPDATES, betaState, entitlementOf, updateCharged,
} from '@/lib/access';
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

  type StoryRow = {
    id: string; slug: string; media_prefix: string | null;
    manifest: Story; published_at: string | null; credit_consumed: boolean;
    update_count: number;
  };
  let story: StoryRow | null = null;
  try {
    story = await one<StoryRow>(
      `select id, slug, media_prefix, manifest, published_at,
              coalesce(credit_consumed, false) as credit_consumed,
              coalesce(update_count, 0) as update_count
         from stories where id = $1 and user_id = $2`,
      [parsed.data.storyId, owner.user_id]);
  } catch {
    // 010 迁移还没跑。**发布是用户花过钱的动作，
    // 绝不能因为少一列就整个 500** —— 当作从没更新过即可
    story = await one<StoryRow>(
      `select id, slug, media_prefix, manifest, published_at,
              coalesce(credit_consumed, false) as credit_consumed,
              0 as update_count
         from stories where id = $1 and user_id = $2`,
      [parsed.data.storyId, owner.user_id]);
  }
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

  const beta = await betaState();
  type UserRow = {
    story_credits: number;
    subscription_status: string | null;
    subscription_until: string | null;
    credit_half: number;
  };
  let user: UserRow | null = null;
  try {
    user = await one<UserRow>(
      `select story_credits, subscription_status, subscription_until,
              coalesce(credit_half, 0) as credit_half
         from users where id = $1`, [owner.user_id]);
  } catch {
    user = await one<UserRow>(
      `select story_credits, subscription_status, subscription_until,
              0 as credit_half
         from users where id = $1`, [owner.user_id]);
  }
  const ent = entitlementOf(user ?? null, beta);

  let consumed = false;
  let charged = 0;          // 这次实际扣了多少篇（0 / 0.5 / 1）
  let updateCount = story.update_count;
  const isUpdate = story.credit_consumed;   // 之前已经发布并扣过了

  if (!isUpdate) {
    // ── 第一次发布: 扣 1 篇 ──
    // 额度只扣一次。续传、重试、手滑点两下都不该再扣
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
      charged = 1;
    }
    await one(
      'update stories set credit_consumed = true where id = $1', [story.id]);
  } else {
    // ── 更新: 前 FREE_UPDATES 次免费，之后每次 0.5 篇 ──
    updateCount = story.update_count + 1;
    // 计次失败（迁移没跑）就当没计 —— 少收一次钱远好过让发布失败
    await one('update stories set update_count = $2 where id = $1',
      [story.id, updateCount]).catch(() => {});

    // 每 5 次收一次 0.5 篇: 第 6、11、16... 次
    if (ent.consumesCredit && updateCharged(updateCount)) {
      // 0.5 篇用整数记账: 先记半篇，凑满一篇再扣 1。
      // 浮点数记钱迟早出现 0.30000000000000004
      const half = (user?.credit_half ?? 0) + 1;
      if (half >= 2) {
        if ((user?.story_credits ?? 0) < 1) {
          return NextResponse.json(
            { error: 'NEED_PAYMENT',
              message: `每 ${FREE_UPDATES} 次更新收 0.5 篇，额度不够了` },
            { status: 402 });
        }
        await one(
          `update users set story_credits = story_credits - 1,
                  credit_half = 0 where id = $1`, [owner.user_id])
            .catch(() => {});
      } else {
        await one('update users set credit_half = 1 where id = $1',
          [owner.user_id]).catch(() => {});
      }
      charged = 0.5;
    }
  }

  await one(
    `update stories set published_at = coalesce(published_at, now()),
            updated_at = now() where id = $1`, [story.id]);

  return NextResponse.json({
    ok: true,
    slug: story.slug,
    consumed,
    charged,
    updateCount,
    freeUpdates: FREE_UPDATES,
  });
}
