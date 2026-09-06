import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/lib/admin';
import { query } from '@/lib/db';
import UserRow from '@/components/UserRow';

export const dynamic = 'force-dynamic';

type Row = {
  id: string; email: string; name: string | null;
  created_at: string; is_admin: boolean; banned_at: string | null;
  story_credits: number; subscription_status: string | null;
  stories: string; views: string;
};

export default async function AdminUsers({
  searchParams,
}: { searchParams: Promise<{ q?: string }> }) {
  const admin = await requireAdmin();
  if (!admin) notFound();

  const { q } = await searchParams;
  const term = (q ?? '').trim();

  const users = await query<Row>(
    `select u.id, u.email, u.name, u.created_at, u.is_admin, u.banned_at,
            u.story_credits, u.subscription_status,
            (select count(*) from stories s where s.user_id = u.id)::text
              as stories,
            (select coalesce(sum(s.view_count),0) from stories s
              where s.user_id = u.id)::text as views
       from users u
      where ($1 = '' or u.email ilike '%'||$1||'%' or u.name ilike '%'||$1||'%')
      order by u.created_at desc
      limit 200`, [term]);

  return (
    <main className="mx-auto max-w-5xl px-6 py-14">
      <div className="mb-8 flex items-center justify-between">
        <h1 className="text-3xl font-semibold tracking-tight">用户</h1>
        <Link href="/admin" className="text-sm text-muted hover:text-paper">
          &larr; 数据总览
        </Link>
      </div>

      <form className="mb-6">
        <input
          name="q" defaultValue={term} placeholder="按邮箱或名字搜索"
          className="w-full max-w-sm rounded-xl border border-white/15 bg-white/5
            px-4 py-2.5 text-sm outline-none focus:border-accentBright"
        />
      </form>

      <div className="overflow-x-auto">
        <table className="w-full min-w-[720px] text-sm">
          <thead className="text-xs text-muted">
            <tr className="border-b border-white/10">
              <th className="py-2 text-left font-normal">用户</th>
              <th className="py-2 text-right font-normal">故事</th>
              <th className="py-2 text-right font-normal">浏览</th>
              <th className="py-2 text-right font-normal">额度</th>
              <th className="py-2 text-right font-normal">注册</th>
              <th className="py-2 text-right font-normal">操作</th>
            </tr>
          </thead>
          <tbody>
            {users.map((u) => (
              <UserRow key={u.id} u={{
                ...u,
                created_at: String(u.created_at).slice(0, 10),
                banned: !!u.banned_at,
                self: u.id === admin.id,
              }} />
            ))}
          </tbody>
        </table>
      </div>

      {users.length === 0 && (
        <p className="mt-6 text-sm text-muted">没有匹配的用户</p>
      )}
    </main>
  );
}
