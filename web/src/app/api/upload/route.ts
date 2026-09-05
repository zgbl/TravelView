import { NextResponse } from 'next/server';
import {
  isLocal, maxUploadBytes, safeKey, verifyUpload, writeLocal,
} from '@/lib/storage';

/**
 * 本地磁盘驱动下的图片上传口。
 *
 * 桌面端拿的是 /api/publish 返回的一次性票据，这里只验票据、写文件。
 * **不看登录状态** —— 票据本身就是授权，和 S3 预签名地址一个道理。
 *
 * 三道闸: 票据必须没过期且签名正确、key 必须是规定的形状（防目录穿越）、
 * 只收 WebP 且有大小上限。任何一道不过就直接拒。
 */
export const runtime = 'nodejs';

export async function PUT(req: Request) {
  if (!isLocal) {
    return NextResponse.json({ error: '本站用的是对象存储，不走这个口' },
      { status: 404 });
  }

  const url = new URL(req.url);
  const rawKey = url.searchParams.get('key') ?? '';
  const exp = url.searchParams.get('exp') ?? '';
  const sig = url.searchParams.get('sig') ?? '';

  const key = safeKey(rawKey);
  if (!key) {
    return NextResponse.json({ error: '文件路径不合法' }, { status: 400 });
  }
  if (!verifyUpload(key, exp, sig)) {
    return NextResponse.json({ error: '上传票据无效或已过期' },
      { status: 403 });
  }

  const type = req.headers.get('content-type') ?? '';
  if (!type.startsWith('image/webp')) {
    return NextResponse.json({ error: '只接受 WebP' }, { status: 415 });
  }

  const body = Buffer.from(await req.arrayBuffer());
  if (body.length === 0) {
    return NextResponse.json({ error: '空文件' }, { status: 400 });
  }
  if (body.length > maxUploadBytes) {
    return NextResponse.json({ error: '文件太大' }, { status: 413 });
  }
  // RIFF....WEBP —— 光信 Content-Type 不够，客户端说什么都可以
  if (body.subarray(0, 4).toString('ascii') !== 'RIFF' ||
      body.subarray(8, 12).toString('ascii') !== 'WEBP') {
    return NextResponse.json({ error: '这不是 WebP 文件' }, { status: 415 });
  }

  await writeLocal(key, body);
  return NextResponse.json({ ok: true, bytes: body.length });
}
