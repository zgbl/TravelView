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
    start_date: string | null; end_date: string | null;
    credit_consumed: boolean; published_at: string | null;
  }>(
    `select slug, media_prefix, manifest, start_date, end_date,
            coalesce(credit_consumed, false) as credit_consumed, published_at
       from stories where id = $1 and user_id = $2`, [id, user.id]);
  if (!row) return NextResponse.json({ error: '找不到' }, { status: 404 });

  /**
   * 删掉**重复发布**的那一篇，把当时扣的额度退回来。
   *
   * 判定"重复"的方式: 删掉它之后，还剩下至少一篇日期重叠的已发布故事。
   * 也就是说这趟行程本来就还在网上，这一篇纯属多发的 —— 那笔钱不该收。
   *
   * 为什么不是"删了就退": 那等于发一篇、删一篇、再发一篇，无限白嫖。
   * 要求"必须还留着一篇"，就把退款限定在真正的误操作上。
   */
  let refunded = false;
  if (row.credit_consumed && row.start_date && row.end_date) {
    const dup = await one<{ n: string }>(
      `select count(*)::text as n from stories
        where user_id = $1 and id <> $2 and published_at is not null
          and start_date <= $4 and end_date >= $3`,
      [user.id, id, row.start_date, row.end_date]);
    if (Number(dup?.n ?? 0) > 0) {
      await one(
        'update users set story_credits = story_credits + 1 where id = $1',
        [user.id]);
      refunded = true;
    }
  }

  // 老数据没有 media_prefix，退回它当年用的 s/<slug>
  const prefix = row.media_prefix ?? `s/${row.slug}`;
  const keys = [
    ...row.manifest.photos.map((p) => `${prefix}/${p.web.path}`),
    ...row.manifest.photos.filter((p) => p.thumb)
      .map((p) => `${prefix}/${p.thumb}`),
  ];
  await deleteStoryMedia(prefix, keys).catch(() => {});
  await query('delete from stories where id = $1', [id]);
  return NextResponse.json({ ok: true, refunded });
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
