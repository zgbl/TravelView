import { S3Client, DeleteObjectsCommand } from '@aws-sdk/client-s3';
import { PutObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import {
  isLocal, removeLocalPrefix, safePrefix, signUpload,
} from './storage';

/**
 * 对象存储。**任何 S3 兼容的服务都行**，靠 `S3_ENDPOINT` 切换:
 *
 *   - Cloudflare R2  零出网费，图片型产品成本几乎全在流量上
 *   - OCI Object Storage  和你的服务器同机房，走内网不计费
 *   - MinIO / 自建     跑在自己机器上
 *
 * 不写死供应商，是因为搬家的成本必须只有一行环境变量。
 * 这里只存用户明确发布的派生图（WebP，100-300KB 一张）。**原图永远不上传。**
 */
const endpoint = process.env.S3_ENDPOINT ??
  `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`;

export const r2 = new S3Client({
  region: process.env.S3_REGION ?? 'auto',
  endpoint,
  // OCI / MinIO 走 path-style，R2 两种都行
  forcePathStyle: (process.env.S3_FORCE_PATH_STYLE ?? '') === 'true',
  credentials: {
    accessKeyId: process.env.S3_ACCESS_KEY_ID ??
      process.env.R2_ACCESS_KEY_ID ?? '',
    secretAccessKey: process.env.S3_SECRET_ACCESS_KEY ??
      process.env.R2_SECRET_ACCESS_KEY ?? '',
  },
});

const BUCKET = process.env.S3_BUCKET ?? process.env.R2_BUCKET ?? 'travelview';

/**
 * 桌面端拿着这个 URL 直传。
 *
 * S3 驱动是预签名地址，图片根本不经过我们的服务器；
 * 本地驱动是我们自己签的一次性上传票据，指回本站的 /api/upload。
 */
export async function presignUpload(key: string, contentType: string) {
  if (isLocal) {
    const exp = Date.now() + 30 * 60 * 1000;
    const sig = signUpload(key, exp);
    const base = (process.env.NEXT_PUBLIC_SITE_URL ?? '')
      .replace(/\/+$/, '');
    return `${base}/api/upload?key=${encodeURIComponent(key)}` +
      `&exp=${exp}&sig=${sig}`;
  }
  const cmd = new PutObjectCommand({
    Bucket: BUCKET,
    Key: key,
    ContentType: contentType,
  });
  return getSignedUrl(r2, cmd, { expiresIn: 60 * 30 });
}

/**
 * 删掉一篇 Story 的图片。
 *
 * 本地驱动删整个目录（比逐个删可靠，也顺手清掉残留的孤儿文件）；
 * 对象存储没有"目录"，只能按 key 逐个删。
 * prefix 必须传进来而不是从 key 里猜 —— 两种路径形状并存，猜错就删错东西。
 */
export async function deleteStoryMedia(prefix: string, keys: string[]) {
  if (isLocal) {
    if (safePrefix(prefix)) await removeLocalPrefix(prefix);
    return;
  }
  await deletePrefix(keys);
}

export async function deletePrefix(keys: string[]) {
  if (!keys.length) return;
  if (isLocal) {
    // 兼容老调用: key 形如 s/<slug>/photos/x.webp
    const dirs = new Set(keys.map((k) => k.split('/').slice(0, -2).join('/')));
    for (const d of dirs) await removeLocalPrefix(d);
    return;
  }
  // 一次最多 1000 个
  for (let i = 0; i < keys.length; i += 1000) {
    await r2.send(new DeleteObjectsCommand({
      Bucket: BUCKET,
      Delete: { Objects: keys.slice(i, i + 1000).map((Key) => ({ Key })) },
    }));
  }
}
