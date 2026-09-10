import NextAuth from 'next-auth';
import Credentials from 'next-auth/providers/credentials';
import bcrypt from 'bcryptjs';
import { one } from './db';

/**
 * Auth.js（NextAuth v5）+ 普通 Postgres。
 *
 * 为什么不用 Supabase Auth: 它会把用户表和会话绑在 Supabase 上，
 * 将来想搬到你 OCI 那台就得改代码。Auth.js 只依赖 TRAVELVIEW_DATABASE_URL，
 * 换 host 不用动逻辑。Supabase 仍然可以用 —— 当成一个 Postgres 供应商即可。
 */
export const { handlers, auth, signIn, signOut } = NextAuth({
  session: { strategy: 'jwt' },
  pages: { signIn: '/login' },
  providers: [
    Credentials({
      credentials: { email: {}, password: {} },
      async authorize(creds) {
        const email = String(creds?.email ?? '').trim().toLowerCase();
        const password = String(creds?.password ?? '');
        if (!email || !password) return null;

        const user = await one<{
          id: string;
          email: string;
          name: string | null;
          password_hash: string | null;
        }>('select id, email, name, password_hash from users where email = $1',
          [email]);

        if (!user?.password_hash) return null;
        const ok = await bcrypt.compare(password, user.password_hash);
        if (!ok) return null;
        return { id: user.id, email: user.email, name: user.name ?? undefined };
      },
    }),
  ],
  callbacks: {
    async jwt({ token, user }) {
      if (user?.id) token.uid = user.id;
      return token;
    },
    async session({ session, token }) {
      if (token.uid) (session.user as any).id = token.uid;
      return session;
    },
  },
});

export async function requireUser() {
  const session = await auth();
  const id = (session?.user as any)?.id as string | undefined;
  if (!id) return null;
  return { id, email: session!.user!.email!, name: session!.user!.name };
}

/**
 * 从**会话 cookie 或发布令牌**里认出用户。
 *
 * 网页走 cookie，桌面端和手机端走 `Authorization: Bearer tv_xxx`。
 * 同一件事（删除自己的 Story、改标题）两边都该能做，
 * 没有理由只让浏览器做 —— 手机上发出去的东西，得能在手机上删掉。
 */
export async function requireUserOrToken(req: Request) {
  const session = await requireUser();
  if (session) return session;

  const token = (req.headers.get('authorization') ?? '')
    .replace(/^Bearer\s+/i, '').trim();
  if (!token) return null;

  const row = await one<{ user_id: string; email: string; name: string | null }>(
    `select u.id as user_id, u.email, u.name
       from publish_tokens t join users u on u.id = t.user_id
      where t.token = $1 and t.revoked_at is null`, [token]);
  if (!row) return null;
  return { id: row.user_id, email: row.email, name: row.name };
}
