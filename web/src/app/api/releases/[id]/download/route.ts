import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { Readable } from 'node:stream';
import { NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { releaseById, releasePath } from '@/lib/releases';

export const dynamic = 'force-dynamic';

/**
 * 下载一个安装包。
 *
 * **流式发送，不整个读进内存。** 一个 200MB 的 dmg 用 readFile 发，
 * 十个人同时下就是 2GB 常驻内存。
 */
export async function GET(
  _req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;               // Next 15: params 是 Promise
  const rel = await releaseById(id);
  if (!rel) return new NextResponse('没有这个版本', { status: 404 });
  if (rel.externalUrl) return NextResponse.redirect(rel.externalUrl);
  if (!rel.filename) return new NextResponse('这个版本没有文件', { status: 404 });

  const file = releasePath(rel.platform, rel.version, rel.filename);
  let size = rel.bytes;
  try {
    size = (await stat(file)).size;
  } catch {
    return new NextResponse('安装包丢了', { status: 404 });
  }

  // 计数失败不该让下载失败 —— 统计是次要的
  void query(`update app_releases set downloads = downloads + 1 where id = $1`,
    [id]).catch(() => {});

  const stream = Readable.toWeb(createReadStream(file)) as ReadableStream;
  return new NextResponse(stream, {
    headers: {
      'content-type': 'application/octet-stream',
      'content-length': String(size),
      // 浏览器直接下载，不要试图在页面里打开
      'content-disposition':
        `attachment; filename="${encodeURIComponent(rel.filename)}"`,
      'cache-control': 'public, max-age=3600',
    },
  });
}
