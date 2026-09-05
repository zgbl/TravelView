import { NextResponse } from 'next/server';
import { randomBytes } from 'crypto';
import { z } from 'zod';
import { one, query } from '@/lib/db';
import { presignUpload } from '@/lib/r2';

/**
 * 桌面端发布接口。
 *
 * 认证用 publish token（用户在 /account 生成后粘进 App），
 * **不让 App 碰用户密码**，也不用做 OAuth 设备流那一套 —— 这是最短的路。
 *
 * 两步:
 *   1. POST /api/publish  带上 manifest 和要上传的文件清单
 *      -> 校验权益、扣一次额度、建 story、返回一批预签名上传地址
 *   2. App 用这些地址把 WebP **直传 R2**，图片不经过我们的服务器
 *
 * **原图永远不在这条链路里。** manifest 里也不允许出现原图路径。
 */
const Body = z.object({
  manifest: z.object({
    version: z.number(),
    title: z.string().min(1),
    subtitle: z.string().optional(),
    start: z.string(),
    end: z.string(),
    cover: z.string().optional(),
    stats: z.object({
      days: z.number(), stops: z.number(),
      photos: z.number(), distanceMeters: z.number(),
    }),
  }).passthrough(),
  files: z.array(z.object({
    path: z.string(),                       // photos/xxx.webp
    contentType: z.string().default('image/webp'),
    bytes: z.number().optional(),
  })).max(400),
  visibility: z.enum(['public', 'unlisted']).default('public'),
});

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
    return NextResponse.json(
      { error: parsed.error.issues[0]?.message ?? '数据格式不对' },
      { status: 400 });
  }
  const { manifest, files, visibility } = parsed.data;

  // 防呆: manifest 里出现原图后缀说明 App 那边出了问题，直接拒绝
  const asText = JSON.stringify(manifest);
  if (/\.(heic|heif|dng|cr2|nef|arw|jpg|jpeg|png)"/i.test(asText)) {
    return NextResponse.json(
      { error: 'manifest 里出现了原图路径，拒绝发布' }, { status: 400 });
  }

  const user = await one<{
    story_credits: number;
    subscription_status: string | null;
    subscription_until: string | null;
  }>(`select story_credits, subscription_status, subscription_until
        from users where id = $1`, [owner.user_id]);

  const subscribed = user?.subscription_status === 'active' &&
    (!user.subscription_until || new Date(user.subscription_until) > new Date());
  if (!subscribed && (user?.story_credits ?? 0) < 1) {
    return NextResponse.json(
      { error: 'NEED_PAYMENT', message: '还没有可用的发布额度' },
      { status: 402 });
  }

  const slug = randomBytes(5).toString('hex'); // 不可猜测的公开地址
  const story = await one<{ id: string }>(
    `insert into stories
       (user_id, slug, title, subtitle, cover_path, manifest,
        start_date, end_date, day_count, stop_count, photo_count,
        distance_meters, visibility, published_at)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13, now())
     returning id`,
    [owner.user_id, slug, manifest.title, manifest.subtitle ?? null,
     manifest.cover ?? null, manifest,
     manifest.start.slice(0, 10), manifest.end.slice(0, 10),
     manifest.stats.days, manifest.stats.stops, manifest.stats.photos,
     Math.round(manifest.stats.distanceMeters), visibility]);

  if (!subscribed) {
    await one(
      'update users set story_credits = story_credits - 1 where id = $1',
      [owner.user_id]);
  }
  await one('update publish_tokens set last_used_at = now() where token = $1',
    [token]);

  // 图片键统一放在 s/<slug>/ 下，删 Story 时按前缀清理
  const uploads = await Promise.all(files.map(async (f) => {
    const key = `s/${slug}/${f.path.replace(/^\/+/, '')}`;
    return { path: f.path, key, url: await presignUpload(key, f.contentType) };
  }));

  return NextResponse.json({
    slug,
    storyId: story!.id,
    publicUrl: `${process.env.NEXT_PUBLIC_SITE_URL}/s/${slug}`,
    mediaBase: `${process.env.NEXT_PUBLIC_MEDIA_BASE}/s/${slug}`,
    uploads,
  });
}
