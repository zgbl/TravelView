import { createHash } from 'node:crypto';
import { createWriteStream } from 'node:fs';
import { mkdir, rm } from 'node:fs/promises';
import path from 'node:path';
import { Readable, Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { NextResponse } from 'next/server';
import { requireAdmin } from '@/lib/admin';
import { query, one } from '@/lib/db';
import {
  allReleases, isPlatform, maxReleaseBytes, releasePath, releasesDir,
} from '@/lib/releases';

export const dynamic = 'force-dynamic';
// 安装包几十上百 MB，默认的 body 限制拦不住
export const maxDuration = 300;

/** 列出所有版本（后台用） */
export async function GET() {
  if (!(await requireAdmin())) {
    // 404 而不是 403 —— 403 等于告诉别人这里有东西
    return new NextResponse('Not found', { status: 404 });
  }
  return NextResponse.json({ releases: await allReleases() });
}

/**
 * 上传一个新版本。
 *
 * multipart 表单: platform, version, notes, current(可选), 以及
 * file（安装包）或 externalUrl（App Store 之类）二选一。
 */
export async function POST(req: Request) {
  if (!(await requireAdmin())) {
    return new NextResponse('Not found', { status: 404 });
  }

  const form = await req.formData();
  const platform = String(form.get('platform') ?? '');
  const version = String(form.get('version') ?? '').trim();
  const notes = String(form.get('notes') ?? '').trim();
  const externalUrl = String(form.get('externalUrl') ?? '').trim();
  const makeCurrent = form.get('current') !== null;
  const file = form.get('file');

  if (!isPlatform(platform)) {
    return NextResponse.json({ error: '平台不对' }, { status: 400 });
  }
  // 版本号形状卡死: 它会变成磁盘上的目录名
  if (!/^\d+\.\d+(\.\d+)?([-+][A-Za-z0-9.]+)?$/.test(version)) {
    return NextResponse.json(
      { error: '版本号要像 1.2.0 这样' }, { status: 400 });
  }
  if (externalUrl && !/^https:\/\//i.test(externalUrl)) {
    return NextResponse.json(
      { error: '外部下载地址必须是 https' }, { status: 400 });
  }
  if (!(file instanceof File) && !externalUrl) {
    return NextResponse.json(
      { error: '要么上传安装包，要么给一个外部下载地址' }, { status: 400 });
  }

  let filename: string | null = null;
  let bytes = 0;
  let checksum: string | null = null;

  if (file instanceof File && file.size > 0) {
    if (file.size > maxReleaseBytes) {
      return NextResponse.json({ error: '文件超过 500MB' }, { status: 413 });
    }
    // **文件名由服务器决定。** 用户给的名字可能含路径、空格、中文，
    // 而它要走 URL、要落到磁盘上
    const ext = (path.extname(file.name) || '').toLowerCase()
      .replace(/[^a-z0-9.]/g, '');
    filename = `TravelView-${version}-${platform}${ext}`;
    const dest = releasePath(platform, version, filename);
    await mkdir(path.dirname(dest), { recursive: true });

    /**
     * **边写盘边算 sha256，而不是先读进内存。**
     *
     * 原来是 `await file.arrayBuffer()` → `Buffer.from()` → 再算哈希:
     * 一个 100MB 的包会在内存里同时存在三份（File 自己一份、arrayBuffer 一份、
     * Buffer 一份），而这台机和 TensuGo 共用 —— 传两次就够把内存吃紧。
     */
    const hash = createHash('sha256');
    let n = 0;
    const tap = new Transform({
      transform(chunk, _enc, cb) {
        hash.update(chunk);
        n += chunk.length;
        cb(null, chunk);
      },
    });
    const t0 = Date.now();
    try {
      await pipeline(
        Readable.fromWeb(file.stream() as Parameters<typeof Readable.fromWeb>[0]),
        tap,
        createWriteStream(dest));
    } catch (e) {
      // 半截文件不要留在磁盘上冒充一个完整安装包
      await rm(dest, { force: true }).catch(() => {});
      const m = e instanceof Error ? e.message : String(e);
      return NextResponse.json({ error: `写盘失败: ${m}` }, { status: 500 });
    }
    bytes = n;
    checksum = hash.digest('hex');
    console.log(`[releases] ${filename} ${(bytes / 1048576).toFixed(1)}MB `
      + `落盘 ${Date.now() - t0}ms -> ${dest}`);
  }

  try {
    // **先落库再切当前版本，两步都在一个事务里** ——
    // 中间失败会留下一个"没有当前版本"的平台，下载页就空了
    await query('begin');
    const row = await one<{ id: string }>(
      `insert into app_releases
         (platform, version, filename, bytes, checksum, external_url, notes)
       values ($1,$2,$3,$4,$5,$6,$7)
       on conflict (platform, version) do update set
         filename = coalesce(excluded.filename, app_releases.filename),
         bytes = greatest(excluded.bytes, 0),
         checksum = coalesce(excluded.checksum, app_releases.checksum),
         external_url = nullif(excluded.external_url, ''),
         notes = excluded.notes
       returning id`,
      [platform, version, filename, bytes, checksum, externalUrl || null, notes]);
    if (makeCurrent && row) {
      await query(
        `update app_releases set is_current = false
          where platform = $1 and id <> $2`, [platform, row.id]);
      await query(`update app_releases set is_current = true where id = $1`,
        [row.id]);
    }
    await query('commit');
    return NextResponse.json({ ok: true, id: row?.id });
  } catch (e) {
    await query('rollback').catch(() => {});
    const msg = e instanceof Error ? e.message : String(e);
    if (/app_releases/.test(msg) && /does not exist/.test(msg)) {
      return NextResponse.json(
        { error: '数据库还没跑 011 迁移: npm run db:migrate:apply' },
        { status: 500 });
    }
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}

/** 删掉一个版本，连同磁盘上的文件 */
export async function DELETE(req: Request) {
  if (!(await requireAdmin())) {
    return new NextResponse('Not found', { status: 404 });
  }
  const id = new URL(req.url).searchParams.get('id') ?? '';
  const row = await one<{
    platform: string; version: string; filename: string | null; is_current: boolean;
  }>(`delete from app_releases where id = $1
      returning platform, version, filename, is_current`, [id]);
  if (!row) return NextResponse.json({ error: '没有这个版本' }, { status: 404 });

  if (row.filename) {
    const dir = path.join(releasesDir, row.platform, row.version);
    await rm(dir, { recursive: true, force: true }).catch(() => {});
    // 顺手把这个平台空掉的上层目录也收掉，磁盘上别留一堆空壳
    await rm(path.dirname(dir), { force: true }).catch(() => {});
  }

  /**
   * 删掉的正好是「当前版本」时，把该平台剩下最新的一条顶上来。
   *
   * 不这么做的话，那个平台会从下载页上**凭空消失** —— 站长只会以为下载页坏了，
   * 而真正的原因是他刚删掉了当前版本。
   */
  let promoted: string | null = null;
  if (row.is_current) {
    const next = await one<{ id: string; version: string }>(
      `select id, version from app_releases
        where platform = $1 order by created_at desc limit 1`, [row.platform]);
    if (next) {
      await query('update app_releases set is_current = true where id = $1',
        [next.id]);
      promoted = next.version;
    }
  }

  return NextResponse.json({ ok: true, promoted });
}
