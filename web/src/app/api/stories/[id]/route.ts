import { NextResponse } from 'next/server';
import { requireUser } from '@/lib/auth';
import { one, query } from '@/lib/db';
import { deleteStoryMedia } from '@/lib/r2';
import type { Story } from '@/lib/story';

/** 删除自己的 Story，连同 R2 上的图片一起清掉 */
export async function DELETE(
  _req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const user = await requireUser();
  if (!user) return NextResponse.json({ error: '请先登录' }, { status: 401 });
  const { id } = await params;

  const row = await one<{
    slug: string; media_prefix: string | null; manifest: Story;
  }>(
    `select slug, media_prefix, manifest
       from stories where id = $1 and user_id = $2`, [id, user.id]);
  if (!row) return NextResponse.json({ error: '找不到' }, { status: 404 });

  // **删除不退额度。** 额度是"发布这个动作"的代价，
  // 东西已经上线过了，删掉是用户自己的决定。
  // 退款听着体贴，实际会变成"发一篇删一篇"的白嫖口子，
  // 而重复发布的代价我们已经在发布前明确告知过了。

  // 老数据没有 media_prefix，退回它当年用的 s/<slug>
  const prefix = row.media_prefix ?? `s/${row.slug}`;
  const keys = [
    ...row.manifest.photos.map((p) => `${prefix}/${p.web.path}`),
    ...row.manifest.photos.filter((p) => p.thumb)
      .map((p) => `${prefix}/${p.thumb}`),
  ];
  await deleteStoryMedia(prefix, keys).catch(() => {});
  await query('delete from stories where id = $1', [id]);
  return NextResponse.json({ ok: true });
}

/** 改可见性 */
export async function PATCH(
  req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const user = await requireUser();
  if (!user) return NextResponse.json({ error: '请先登录' }, { status: 401 });
  const { id } = await params;
  const { visibility } = await req.json().catch(() => ({}));
  if (!['public', 'unlisted', 'private'].includes(visibility)) {
    return NextResponse.json({ error: '取值不对' }, { status: 400 });
  }
  await query(
    'update stories set visibility = $1, updated_at = now() where id = $2 and user_id = $3',
    [visibility, id, user.id]);
  return NextResponse.json({ ok: true });
}
