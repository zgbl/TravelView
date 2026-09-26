import { NextResponse, type NextRequest } from 'next/server';

export const dynamic = 'force-dynamic';

/**
 * GET /api/headers
 * Cloudflare Assignment requirement:
 * Returns all incoming HTTP request headers directly in the response body as a JSON object.
 */
export async function GET(req: NextRequest) {
  const headersObj: Record<string, string> = {};

  req.headers.forEach((value, key) => {
    headersObj[key] = value;
  });

  return NextResponse.json(headersObj, {
    status: 200,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store, no-cache, must-revalidate, proxy-revalidate',
    },
  });
}
