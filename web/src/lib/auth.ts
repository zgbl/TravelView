import NextAuth from 'next-auth';
import Credentials from 'next-auth/providers/credentials';
import bcrypt from 'bcryptjs';
import { one } from './db';

/**
 * Auth.js（NextAuth v5）+ 普通 Postgres。
 *
 * 为什么不用 Supabase Auth: 它会把用户表和会话绑在 Supabase 上，
 * 将来想搬到你 OCI 那台就得改代码。Auth.js 只依赖 DATABASE_URL，
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
