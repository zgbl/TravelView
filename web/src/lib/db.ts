import { Pool } from 'pg';

/**
 * 一个普通的 Postgres 连接池。
 *
 * 刻意不用某家的 SDK —— 换到 Neon / Supabase / 你 OCI 上那台
 * 只需要改 DATABASE_URL，代码一行不动。
 * 这也是将来能和 TensuGo 共用一个实例的前提。
 */
declare global {
  // eslint-disable-next-line no-var
  var __tvPool: Pool | undefined;
}

export const pool =
  global.__tvPool ??
  new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.DATABASE_URL?.includes('sslmode=disable')
      ? undefined
      : { rejectUnauthorized: false },
    max: 5,
  });

if (process.env.NODE_ENV !== 'production') global.__tvPool = pool;

export async function query<T = any>(sql: string, params: any[] = []) {
  const res = await pool.query(sql, params);
  return res.rows as T[];
}

export async function one<T = any>(sql: string, params: any[] = []) {
  const rows = await query<T>(sql, params);
  return rows[0] ?? null;
}
