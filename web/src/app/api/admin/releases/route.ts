import { createHash } from 'node:crypto';
import { mkdir, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
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
    const buf = Buffer.from(await file.arrayBuffer());
    bytes = buf.length;
    checksum = createHash('sha256').update(buf).digest('hex');
    const dest = releasePath(platform, version, filename);
    await mkdir(path.dirname(dest), { recursive: true });
    await writeFile(dest, buf);
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
  const row = await one<{ platform: string; version: string; filename: string | null }>(
    `delete from app_releases where id = $1
      returning platform, version, filename`, [id]);
  if (!row) return NextResponse.json({ error: '没有这个版本' }, { status: 404 });
  if (row.filename) {
    await rm(path.join(releasesDir, row.platform, row.version),
      { recursive: true, force: true }).catch(() => {});
  }
  return NextResponse.json({ ok: true });
}
