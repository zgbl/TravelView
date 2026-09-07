#!/usr/bin/env node
/**
 * 按顺序跑完 db/migrations 下所有迁移。
 *
 *   node scripts/migrate.mjs          # 看看还差哪几条，不写库
 *   node scripts/migrate.mjs --apply  # 真的跑
 *
 * 跑过的记在 schema_migrations 表里，重复执行只会跳过。
 * 迁移文件本身也都写成可重复执行的（if not exists），
 * 所以就算这张表丢了，重跑一遍也不会把数据弄坏。
 *
 * 环境变量: set -a; . /etc/travelview/env; set +a
 */
import { readdir, readFile } from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import pg from 'pg';

const APPLY = process.argv.includes('--apply');
const dir = path.join(path.dirname(fileURLToPath(import.meta.url)),
  '..', 'db', 'migrations');

const db = new pg.Client({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_URL?.includes('sslmode=disable')
    ? undefined : { rejectUnauthorized: false },
});

if (!process.env.DATABASE_URL) {
  console.error('没有 DATABASE_URL。先: set -a; . /etc/travelview/env; set +a');
  process.exit(1);
}

await db.connect();
await db.query(`create table if not exists schema_migrations (
  name text primary key,
  applied_at timestamptz not null default now()
)`);

const done = new Set(
  (await db.query('select name from schema_migrations')).rows.map((r) => r.name));

const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();
const pending = files.filter((f) => !done.has(f));

if (pending.length === 0) {
  console.log(`数据库是最新的（${files.length} 条迁移都跑过了）`);
  await db.end();
  process.exit(0);
}

console.log(`待执行 ${pending.length} 条:`);
for (const f of pending) console.log(`  - ${f}`);

if (!APPLY) {
  console.log('\n加 --apply 才会真的执行。');
  await db.end();
  process.exit(0);
}

for (const f of pending) {
  const sql = await readFile(path.join(dir, f), 'utf8');
  process.stdout.write(`跑 ${f} ... `);
  try {
    // 每条迁移一个事务: 中途失败就整条回滚，不留半截状态
    await db.query('begin');
    await db.query(sql);
    await db.query(
      'insert into schema_migrations (name) values ($1) on conflict do nothing',
      [f]);
    await db.query('commit');
    console.log('好了');
  } catch (e) {
    await db.query('rollback').catch(() => {});
    console.log('失败');
    console.error(`\n${f} 执行失败，后面的没有跑:\n${e.message}\n`);
    await db.end();
    process.exit(1);
  }
}

console.log('\n全部完成。');
await db.end();
