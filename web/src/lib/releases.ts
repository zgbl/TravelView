import path from 'node:path';
import { query, one } from './db';

/**
 * App 安装包。
 *
 * **文件不进数据库**，只记元数据；安装包本身落在 RELEASES_DIR 下。
 * 一个 200MB 的 dmg 塞进 Postgres，备份、迁移、内存占用全都会出问题。
 */
export const releasesDir =
  process.env.RELEASES_DIR ?? path.join(process.cwd(), '.data', 'releases');

export const platforms = ['macos', 'windows', 'android', 'ios'] as const;
export type Platform = (typeof platforms)[number];

export function isPlatform(x: string): x is Platform {
  return (platforms as readonly string[]).includes(x);
}

/// 安装包上限 500MB。桌面端打包出来通常几十 MB，超出这个数多半是传错了东西
export const maxReleaseBytes = 500 * 1024 * 1024;

export type Release = {
  id: string;
  platform: Platform;
  version: string;
  filename: string | null;
  bytes: number;
  checksum: string | null;
  externalUrl: string | null;
  notes: string;
  isCurrent: boolean;
  downloads: number;
  createdAt: string;
};

type Row = {
  id: string; platform: string; version: string; filename: string | null;
  bytes: string | number; checksum: string | null; external_url: string | null;
  notes: string; is_current: boolean; downloads: string | number;
  created_at: string;
};

function toRelease(r: Row): Release {
  return {
    id: r.id,
    platform: r.platform as Platform,
    version: r.version,
    filename: r.filename,
    bytes: Number(r.bytes),
    checksum: r.checksum,
    externalUrl: r.external_url,
    notes: r.notes,
    isCurrent: r.is_current,
    downloads: Number(r.downloads),
    createdAt: r.created_at,
  };
}

/**
 * 每个平台的当前版本。
 *
 * **表不存在时返回空数组，不抛错。** 迁移还没跑的服务器上，
 * 下载页应该显示"还没有发布版本"，而不是整站 500 ——
 * 这个项目已经被没跑的迁移打断过四次了。
 */
export async function currentReleases(): Promise<Release[]> {
  try {
    const rows = await query<Row>(
      `select * from app_releases where is_current order by platform`);
    return rows.map(toRelease);
  } catch {
    return [];
  }
}

export async function allReleases(): Promise<Release[]> {
  try {
    const rows = await query<Row>(
      `select * from app_releases order by platform, created_at desc limit 200`);
    return rows.map(toRelease);
  } catch {
    return [];
  }
}

export async function releaseById(id: string): Promise<Release | null> {
  try {
    const r = await one<Row>(`select * from app_releases where id = $1`, [id]);
    return r ? toRelease(r) : null;
  } catch {
    return null;
  }
}

/// 安装包在磁盘上的位置。**文件名由服务器生成**，不用用户给的名字
export function releasePath(platform: string, version: string, filename: string) {
  return path.join(releasesDir, platform, version, path.basename(filename));
}

/**
 * 从 User-Agent 猜平台，用来把下载页上对应的那一块高亮出来。
 *
 * **只是猜，不做重定向。** 猜错了直接给用户下错文件，
 * 比让他自己点一下糟糕得多；四个按钮一直都在。
 */
export function guessPlatform(ua: string): Platform | null {
  const s = ua.toLowerCase();
  if (/android/.test(s)) return 'android';
  if (/iphone|ipad|ipod/.test(s)) return 'ios';
  if (/mac os x|macintosh/.test(s)) return 'macos';
  if (/windows/.test(s)) return 'windows';
  return null;
}

export function platformLabel(p: Platform) {
  return { macos: 'macOS', windows: 'Windows', android: 'Android', ios: 'iOS' }[p];
}

export function humanBytes(n: number) {
  if (n <= 0) return '';
  const u = ['B', 'KB', 'MB', 'GB'];
  let i = 0, v = n;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return `${v.toFixed(v >= 100 || i === 0 ? 0 : 1)} ${u[i]}`;
}
