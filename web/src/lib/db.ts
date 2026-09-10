import { Pool } from 'pg';

/**
 * 一个普通的 Postgres 连接池。
 *
 * 刻意不用某家的 SDK —— 换到 Neon / Supabase / 你 OCI 上那台
 * 只需要改 TRAVELVIEW_DATABASE_URL，代码一行不动。
 * 这也是将来能和 TensuGo 共用一个实例的前提。
 *
 * 变量名带产品前缀不是洁癖：这台机上 TensuGo 和 TravelView 共用同一个
 * Postgres，登录 shell 里那个裸 DATABASE_URL 指向的是另一个产品的库。
 * 所以这里只认 TRAVELVIEW_DATABASE_URL，并且**故意不给裸 DATABASE_URL
 * 留回退** —— 回退不叫兼容，叫连上别人的库往里写。
 */
export function databaseUrl(): string | undefined {
  return process.env.TRAVELVIEW_DATABASE_URL?.trim() || undefined;
}

function requireDatabaseUrl(): string {
  const url = databaseUrl();
  if (url) return url;
  const misnamed = process.env.DATABASE_URL
    ? ' 检测到裸 DATABASE_URL，已按新规矩忽略它：请改名为 TRAVELVIEW_DATABASE_URL。'
    : '';
  throw new Error(`TRAVELVIEW_DATABASE_URL 未设置。${misnamed}`);
}

declare global {
  // eslint-disable-next-line no-var
  var __tvPool: Pool | undefined;
}

// 这里刻意不 throw：next build 也会加载这个模块，构建期没有这个变量是正常的。
// 真缺变量时，第一条 SQL 会带着上面的原因炸掉，而不是悄悄连到 localhost。
const initialUrl = databaseUrl();

export const pool =
  global.__tvPool ??
  new Pool({
    connectionString: initialUrl,
    ssl: initialUrl?.includes('sslmode=disable')
      ? undefined
      : { rejectUnauthorized: false },
    max: 5,
  });

if (process.env.NODE_ENV !== 'production') global.__tvPool = pool;

export async function query<T = any>(sql: string, params: any[] = []) {
  requireDatabaseUrl();
  const res = await pool.query(sql, params);
  return res.rows as T[];
}

export async function one<T = any>(sql: string, params: any[] = []) {
  const rows = await query<T>(sql, params);
  return rows[0] ?? null;
}
