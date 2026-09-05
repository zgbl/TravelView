import { createHmac, timingSafeEqual } from 'crypto';
import { mkdir, rm, writeFile } from 'fs/promises';
import path from 'path';

/**
 * 发布图片的存放位置。
 *
 * 两种驱动，靠 `STORAGE_DRIVER` 切换:
 *   - `local`  存服务器本地磁盘（现在用这个），nginx 直接把目录发出去
 *   - `s3`     任何 S3 兼容服务（OCI Object Storage / R2 / MinIO）
 *
 * 之所以要这层抽象: 本地磁盘最省事，但**它是有上限的** ——
 * 磁盘满了、想上 CDN、想换机器，都得能一行环境变量搬走。
 * 两种驱动对外接口完全一样，桌面端和数据库都感知不到区别。
 *
 * 无论哪种驱动，存进来的都只有用户明确发布的派生图（WebP，已剥 EXIF）。
 * **原图永远不上传。**
 */
export const driver = process.env.STORAGE_DRIVER ?? 's3';
export const isLocal = driver === 'local';

/** 本地磁盘的根目录。**必须在仓库外面** —— 部署时会整个覆盖代码目录。 */
export const mediaRoot =
  process.env.MEDIA_ROOT ?? '/var/lib/travelview/media';

const uploadSecret =
  process.env.UPLOAD_SECRET ?? process.env.AUTH_SECRET ?? '';

/** 单张图上限。派生图正常 100-300KB，10MB 已经是极宽松的兜底。 */
export const maxUploadBytes = 10 * 1024 * 1024;

/**
 * 上传票据。
 *
 * 本地驱动没有 S3 的预签名，所以自己签一个: 服务端用 HMAC 签
 * `key + 过期时间`，桌面端拿着它 PUT 回来。这样**不用把任何长期凭证
 * 交给客户端**，票据也只在半小时内、只对这一个 key 有效。
 */
export function signUpload(key: string, expiresAt: number) {
  return createHmac('sha256', uploadSecret)
    .update(`${key}\n${expiresAt}`)
    .digest('base64url');
}

export function verifyUpload(key: string, exp: string, sig: string) {
  const expiresAt = Number(exp);
  if (!Number.isFinite(expiresAt) || expiresAt < Date.now()) return false;
  const want = Buffer.from(signUpload(key, expiresAt));
  const got = Buffer.from(sig);
  return want.length === got.length && timingSafeEqual(want, got);
}

/**
 * key 必须长成 `s/<slug>/photos|thumbs/<name>.webp`。
 *
 * 这是安全边界，不是格式洁癖: 放任 key 里出现 `..` 或绝对路径，
 * 一次上传就能写到磁盘上任何地方。
 */
export function safeKey(key: string): string | null {
  if (!/^s\/[a-z0-9]{4,32}\/(photos|thumbs)\/[A-Za-z0-9._-]{1,80}\.webp$/
      .test(key)) {
    return null;
  }
  if (key.includes('..')) return null;
  return key;
}

export function localPathFor(key: string) {
  return path.join(mediaRoot, key);
}

export async function writeLocal(key: string, data: Buffer) {
  const file = localPathFor(key);
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, data);
}

/** 删一整篇 Story 的图片。本地驱动直接删目录，比逐个删可靠。 */
export async function removeLocalStory(slug: string) {
  if (!/^[a-z0-9]{4,32}$/.test(slug)) return;
  await rm(path.join(mediaRoot, 's', slug), { recursive: true, force: true });
}
