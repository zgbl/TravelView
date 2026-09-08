import { NextResponse } from 'next/server';
import { randomBytes } from 'crypto';
import { z } from 'zod';
import { one, query } from '@/lib/db';
import { deleteStoryMedia, presignUpload } from '@/lib/r2';
import { mediaPrefixFor } from '@/lib/storage';
import { siteUrl } from '@/lib/stripe';
import { betaState, entitlementOf } from '@/lib/access';

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
  /**
   * 传了就是**原地更新那一篇**: URL 不变、不再扣额度。
   * 桌面端记住上次发布返回的 storyId，用户改个错别字或补几张照片
   * 不会变成第二篇，已经分享出去的链接也不会失效。
   */
  storyId: z.string().uuid().optional(),
});

/** 令牌换用户。桌面端只有令牌，没有会话。 */
async function userIdForToken(token: string) {
  const owner = await one<{ user_id: string }>(
    `select user_id from publish_tokens
      where token = $1 and revoked_at is null`, [token]);
  return owner?.user_id ?? null;
}

export async function POST(req: Request) {
  const token = (req.headers.get('authorization') ?? '')
    .replace(/^Bearer\s+/i, '').trim();
  if (!token) return NextResponse.json({ error: '缺少发布令牌' }, { status: 401 });

  const userId = await userIdForToken(token);
  if (!userId) return NextResponse.json({ error: '令牌无效' }, { status: 401 });

  const parsed = Body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0]?.message ?? '数据格式不对' },
      { status: 400 });
  }
  const { manifest, files, visibility, storyId } = parsed.data;

  // 防呆: manifest 里出现原图格式说明 App 那边出了问题，直接拒绝。
  // jpg 不在这个名单里 —— 系统编不出 WebP 时导出的就是 JPEG 派生图。
  // 真正兜住"不许传原图"的是下面这条路径形状检查 + safeKey:
  // 只有导出目录里 photos/ 和 thumbs/ 下的文件才可能被上传。
  /**
   * 配乐字段消毒。**在服务器上做，不能只信桌面端** ——
   * 这个字段最后会变成页面上的 <audio src>，任何人拿到令牌都能直接
   * POST 上来。只放行曲库 id 和 https 链接: http 会让整页变成混合内容，
   * 而 javascript:/data: 这类根本不该出现在这里。
   */
  const rawMusic = (manifest as { music?: unknown }).music;
  if (typeof rawMusic === 'string') {
    const m = rawMusic.trim();
    const ok = /^[a-z0-9_-]{1,32}$/i.test(m) || /^https:\/\/[^\s]{5,500}$/i.test(m);
    if (ok) (manifest as { music?: string }).music = m;
    else delete (manifest as { music?: string }).music;
  } else {
    delete (manifest as { music?: string }).music;
  }

  const asText = JSON.stringify(manifest);
  if (/\.(heic|heif|dng|cr2|nef|arw|raf|orf|rw2|tif|tiff)"/i.test(asText)) {
    return NextResponse.json(
      { error: 'manifest 里出现了原图路径，拒绝发布' }, { status: 400 });
  }
  const badPath = files.find(
    (f) => !/^((photos|thumbs)\/[A-Za-z0-9._-]{1,80}\.(webp|jpg|jpeg)|og\.jpg)$/i
      .test(f.path.replace(/^\/+/, '')));
  if (badPath) {
    return NextResponse.json(
      { error: `不允许的文件路径: ${badPath.path}` }, { status: 400 });
  }

  const user = await one<{
    story_credits: number;
    subscription_status: string | null;
    subscription_until: string | null;
    banned_at: string | null;
  }>(`select story_credits, subscription_status, subscription_until, banned_at
        from users where id = $1`, [userId]);

  if (user?.banned_at) {
    return NextResponse.json({ error: '这个账号已被停用' }, { status: 403 });
  }

  const beta = await betaState();
  // 这一步只是**先看看有没有资格**，避免让没额度的人白传 80MB。
  // 真正扣款在 complete 那一步
  const ent = entitlementOf(user ?? null, beta);
  if (!ent.allowed) {
    return NextResponse.json(
      { error: 'NEED_PAYMENT', message: '还没有可用的发布额度' },
      { status: 402 });
  }

  // ── 原地更新 ──
  // 找不到就当作新建（用户可能删了那一篇，或者换了账号），
  // 而不是报错把人卡住 —— 他手上的照片已经导出好了
  let existing: { id: string; slug: string; media_prefix: string | null;
    manifest: any } | null = null;
  if (storyId) {
    try {
      existing = await one(
        `select id, slug, media_prefix, manifest from stories
          where id = $1 and user_id = $2`, [storyId, userId]);
    } catch {
      // 008 迁移没跑时没有 media_prefix 列
      existing = await one(
        `select id, slug, null::text as media_prefix, manifest from stories
          where id = $1 and user_id = $2`, [storyId, userId]);
    }
  }

  if (existing) {
    // 这一次没有再出现的旧图要删掉，否则改一次图就在磁盘上留一份垃圾
    const prefix = existing.media_prefix ?? `s/${existing.slug}`;
    const keep = new Set(files.map((f) => f.path.replace(/^\/+/, '')));
    const oldPaths: string[] = [
      ...(existing.manifest?.photos ?? []).map((p: any) => p?.web?.path),
      ...(existing.manifest?.photos ?? []).map((p: any) => p?.thumb),
    ].filter(Boolean);
    const orphans = oldPaths.filter((p) => !keep.has(p))
      .map((p) => `${prefix}/${p}`);
    if (orphans.length) {
      await deleteStoryMedia('', orphans).catch(() => {});
    }

    await one(
      `update stories set title = $2, subtitle = $3, cover_path = $4,
              manifest = $5, start_date = $6, end_date = $7, day_count = $8,
              stop_count = $9, photo_count = $10, distance_meters = $11,
              visibility = $12, updated_at = now()
        where id = $1`,
      [existing.id, manifest.title, manifest.subtitle ?? null,
       manifest.cover ?? null, manifest,
       manifest.start.slice(0, 10), manifest.end.slice(0, 10),
       manifest.stats.days, manifest.stats.stops, manifest.stats.photos,
       Math.round(manifest.stats.distanceMeters), visibility]);

    await one('update publish_tokens set last_used_at = now() where token = $1',
      [token]);

    const uploads = await Promise.all(files.map(async (f) => {
      const key = `${prefix}/${f.path.replace(/^\/+/, '')}`;
      return { path: f.path, key, url: await presignUpload(key, f.contentType) };
    }));

    return NextResponse.json({
      slug: existing.slug,
      storyId: existing.id,
      updated: true,
      publicUrl: `${siteUrl()}/s/${existing.slug}`,
      mediaBase: `${process.env.NEXT_PUBLIC_MEDIA_BASE}/${prefix}`,
      uploads,
    });
  }

  // ── 新建 ──
  const slug = randomBytes(5).toString('hex'); // 不可猜测的公开地址
  // 按用户和年月分目录: 单个用户几万张图时目录还翻得动，也方便整体迁移
  let prefix = mediaPrefixFor(userId, slug);
  const common = [
    userId, slug, manifest.title, manifest.subtitle ?? null,
    manifest.cover ?? null, manifest,
    manifest.start.slice(0, 10), manifest.end.slice(0, 10),
    manifest.stats.days, manifest.stats.stops, manifest.stats.photos,
    Math.round(manifest.stats.distanceMeters), visibility,
  ];

  let story: { id: string } | null = null;
  try {
    story = await one<{ id: string }>(
      `insert into stories
         (user_id, slug, title, subtitle, cover_path, manifest,
          start_date, end_date, day_count, stop_count, photo_count,
          distance_meters, visibility, media_prefix)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
       returning id`,
      [...common, prefix]);
  } catch {
    // 008 迁移还没跑（没有 media_prefix 列）时退回老布局 s/<slug>。
    // 发布是用户花过钱的动作，**绝不能因为少一列就整个 500** ——
    // 老布局照样能正常渲染和删除，读的时候本来就有这条回落
    prefix = `s/${slug}`;
    story = await one<{ id: string }>(
      `insert into stories
         (user_id, slug, title, subtitle, cover_path, manifest,
          start_date, end_date, day_count, stop_count, photo_count,
          distance_meters, visibility)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
       returning id`,
      common);
  }

  // **这里不扣额度。** 图还一张没传呢 ——
  // 传到一半断了却把额度扣掉，等于用户付了钱什么都没拿到。
  // 额度在 /api/publish/complete 里扣，那时候东西才真的交付了。
  await one('update publish_tokens set last_used_at = now() where token = $1',
    [token]);

  const uploads = await Promise.all(files.map(async (f) => {
    const key = `${prefix}/${f.path.replace(/^\/+/, '')}`;
    return { path: f.path, key, url: await presignUpload(key, f.contentType) };
  }));

  return NextResponse.json({
    slug,
    storyId: story!.id,
    updated: false,
    publicUrl: `${siteUrl()}/s/${slug}`,
    mediaBase: `${process.env.NEXT_PUBLIC_MEDIA_BASE}/${prefix}`,
    uploads,
  });
}
