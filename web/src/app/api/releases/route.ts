import { NextResponse } from 'next/server';
import { currentReleases, humanBytes, platformLabel } from '@/lib/releases';

export const dynamic = 'force-dynamic';

/**
 * 各平台的当前版本。**公开接口** —— 客户端用它做"有新版本了"的检查。
 *
 * 故意只给当前版本、不给历史: 自动更新只该往前走，
 * 让客户端能看见旧版本等于给了它退回去的机会。
 */
export async function GET() {
  const rows = await currentReleases();
  return NextResponse.json({
    releases: rows.map((r) => ({
      platform: r.platform,
      label: platformLabel(r.platform),
      version: r.version,
      bytes: r.bytes,
      size: humanBytes(r.bytes),
      checksum: r.checksum,
      notes: r.notes,
      publishedAt: r.createdAt,
      // 外部地址（App Store 之类）优先；否则走我们自己的下载口
      url: r.externalUrl ?? `/api/releases/${r.id}/download`,
    })),
  });
}
