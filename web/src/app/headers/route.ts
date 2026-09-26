import { type NextRequest } from 'next/server';

export const dynamic = 'force-dynamic';

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * GET /headers
 * Renders a clean, minimalistic, modern HTML page displaying all HTTP request headers in a key-value table.
 * Designed specifically for assignment verification, troubleshooting, and report screenshots.
 */
export async function GET(req: NextRequest) {
  const headersList: Array<{ key: string; value: string; isCf: boolean }> = [];
  const headersObj: Record<string, string> = {};

  req.headers.forEach((value, key) => {
    headersObj[key] = value;
    const isCf = key.toLowerCase().startsWith('cf-') || key.toLowerCase() === 'cdn-loop';
    headersList.push({ key, value, isCf });
  });

  // Sort headers: Cloudflare headers first, then alphabetically
  headersList.sort((a, b) => {
    if (a.isCf && !b.isCf) return -1;
    if (!a.isCf && b.isCf) return 1;
    return a.key.localeCompare(b.key);
  });

  const clientIp = req.headers.get('cf-connecting-ip') ||
    req.headers.get('x-forwarded-for')?.split(',')[0].trim() ||
    req.headers.get('x-real-ip') ||
    'Direct / Unknown';

  const cfRay = req.headers.get('cf-ray') || 'None (Direct connection)';
  const cfCountry = req.headers.get('cf-ipcountry') || 'Unknown';
  const host = req.headers.get('host') || 'Unknown';
  const nowUtc = new Date().toISOString();
  const jsonPayload = JSON.stringify(headersObj, null, 2);

  const tableRows = headersList
    .map(
      (h) => `
        <tr class="header-row ${h.isCf ? 'cf-highlight' : ''}" data-key="${escapeHtml(h.key.toLowerCase())}" data-value="${escapeHtml(h.value.toLowerCase())}">
          <td class="key-cell">
            <span class="key-name">${escapeHtml(h.key)}</span>
            ${h.isCf ? '<span class="badge badge-cf">Cloudflare</span>' : ''}
          </td>
          <td class="value-cell">
            <code>${escapeHtml(h.value)}</code>
          </td>
        </tr>
      `
    )
    .join('');

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>TravelView · HTTP Request Headers</title>
  <style>
    :root {
      --bg: #090d16;
      --card-bg: rgba(18, 24, 38, 0.75);
      --card-border: rgba(255, 255, 255, 0.08);
      --text-main: #f1f5f9;
      --text-muted: #94a3b8;
      --accent: #38bdf8;
      --accent-cf: #f97316;
      --accent-cf-bg: rgba(249, 115, 22, 0.15);
      --border-row: rgba(255, 255, 255, 0.05);
      --code-bg: rgba(15, 23, 42, 0.6);
      --highlight: rgba(56, 189, 248, 0.08);
    }
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    body {
      background-color: var(--bg);
      background-image: 
        radial-gradient(at 0% 0%, rgba(56, 189, 248, 0.08) 0px, transparent 50%),
        radial-gradient(at 100% 100%, rgba(249, 115, 22, 0.05) 0px, transparent 50%);
      color: var(--text-main);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      min-height: 100vh;
      padding: 2.5rem 1.5rem;
      -webkit-font-smoothing: antialiased;
    }
    .container {
      max-width: 1080px;
      margin: 0 auto;
    }
    header {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: 1rem;
      margin-bottom: 2rem;
      padding-bottom: 1.5rem;
      border-bottom: 1px solid var(--card-border);
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 0.75rem;
    }
    .logo-circle {
      width: 38px;
      height: 38px;
      border-radius: 10px;
      background: linear-gradient(135deg, #0284c7, #38bdf8);
      display: flex;
      align-items: center;
      justify-content: center;
      font-weight: 700;
      color: #fff;
      font-size: 1.1rem;
      box-shadow: 0 4px 12px rgba(2, 132, 199, 0.3);
    }
    h1 {
      font-size: 1.5rem;
      font-weight: 600;
      letter-spacing: -0.02em;
    }
    .subtitle {
      font-size: 0.85rem;
      color: var(--text-muted);
      margin-top: 0.2rem;
    }
    .actions {
      display: flex;
      align-items: center;
      gap: 0.75rem;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      gap: 0.4rem;
      padding: 0.5rem 0.9rem;
      border-radius: 8px;
      font-size: 0.85rem;
      font-weight: 500;
      text-decoration: none;
      cursor: pointer;
      transition: all 0.15s ease;
      border: 1px solid var(--card-border);
      background: var(--card-bg);
      color: var(--text-main);
    }
    .btn:hover {
      background: rgba(255, 255, 255, 0.08);
      border-color: rgba(255, 255, 255, 0.2);
    }
    .btn-primary {
      background: rgba(56, 189, 248, 0.15);
      color: var(--accent);
      border-color: rgba(56, 189, 248, 0.3);
    }
    .btn-primary:hover {
      background: rgba(56, 189, 248, 0.25);
    }
    .metrics {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 1rem;
      margin-bottom: 2rem;
    }
    .metric-card {
      background: var(--card-bg);
      backdrop-filter: blur(12px);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      padding: 1rem 1.25rem;
    }
    .metric-label {
      font-size: 0.75rem;
      text-transform: uppercase;
      letter-spacing: 0.06em;
      color: var(--text-muted);
      margin-bottom: 0.35rem;
    }
    .metric-val {
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 0.95rem;
      font-weight: 600;
      color: var(--text-main);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .filter-bar {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 1rem;
      margin-bottom: 1rem;
    }
    .search-input {
      flex: 1;
      max-width: 400px;
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 8px;
      padding: 0.55rem 0.85rem;
      color: var(--text-main);
      font-size: 0.85rem;
      outline: none;
      transition: border-color 0.15s ease;
    }
    .search-input:focus {
      border-color: var(--accent);
    }
    .search-input::placeholder {
      color: #64748b;
    }
    .table-container {
      background: var(--card-bg);
      backdrop-filter: blur(12px);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      overflow: hidden;
      box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
    }
    table {
      width: 100%;
      border-collapse: collapse;
      text-align: left;
    }
    th {
      background: rgba(15, 23, 42, 0.8);
      font-size: 0.75rem;
      text-transform: uppercase;
      letter-spacing: 0.06em;
      color: var(--text-muted);
      padding: 0.85rem 1.25rem;
      border-bottom: 1px solid var(--card-border);
    }
    td {
      padding: 0.85rem 1.25rem;
      border-bottom: 1px solid var(--border-row);
      vertical-align: top;
      font-size: 0.88rem;
    }
    tr:last-child td {
      border-bottom: none;
    }
    tr:hover td {
      background: var(--highlight);
    }
    .key-cell {
      width: 32%;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-weight: 500;
      color: #e2e8f0;
      white-space: nowrap;
    }
    .key-name {
      display: inline-block;
      vertical-align: middle;
    }
    .badge {
      display: inline-block;
      vertical-align: middle;
      margin-left: 0.5rem;
      padding: 0.15rem 0.45rem;
      font-size: 0.68rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      border-radius: 4px;
    }
    .badge-cf {
      background: var(--accent-cf-bg);
      color: var(--accent-cf);
      border: 1px solid rgba(249, 115, 22, 0.3);
    }
    .value-cell {
      word-break: break-all;
    }
    code {
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 0.84rem;
      color: #cbd5e1;
    }
    .cf-highlight td {
      background: rgba(249, 115, 22, 0.03);
    }
    footer {
      margin-top: 2rem;
      text-align: center;
      font-size: 0.8rem;
      color: #64748b;
    }
    #toast {
      position: fixed;
      bottom: 2rem;
      right: 2rem;
      background: #0284c7;
      color: #fff;
      padding: 0.6rem 1.2rem;
      border-radius: 8px;
      font-size: 0.85rem;
      font-weight: 500;
      box-shadow: 0 4px 16px rgba(0,0,0,0.4);
      opacity: 0;
      pointer-events: none;
      transition: opacity 0.2s ease, transform 0.2s ease;
      transform: translateY(10px);
    }
    #toast.show {
      opacity: 1;
      transform: translateY(0);
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div class="brand">
        <div class="logo-circle">TV</div>
        <div>
          <h1>HTTP Request Headers Inspector</h1>
          <div class="subtitle">TravelView Origin Web Server · Cloudflare Assignment Diagnostics</div>
        </div>
      </div>
      <div class="actions">
        <a href="/api/headers" class="btn btn-primary" target="_blank">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="16 18 22 12 16 6"></polyline><polyline points="8 6 2 12 8 18"></polyline></svg>
          Raw JSON API
        </a>
        <button id="copyJsonBtn" class="btn">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>
          Copy JSON
        </button>
      </div>
    </header>

    <section class="metrics">
      <div class="metric-card">
        <div class="metric-label">Client IP (Connecting)</div>
        <div class="metric-val" title="${escapeHtml(clientIp)}">${escapeHtml(clientIp)}</div>
      </div>
      <div class="metric-card">
        <div class="metric-label">Cloudflare Ray ID</div>
        <div class="metric-val" title="${escapeHtml(cfRay)}">${escapeHtml(cfRay)}</div>
      </div>
      <div class="metric-card">
        <div class="metric-label">Origin Host / Country</div>
        <div class="metric-val" title="${escapeHtml(host)}">${escapeHtml(host)} (${escapeHtml(cfCountry)})</div>
      </div>
      <div class="metric-card">
        <div class="metric-label">Total Headers Count</div>
        <div class="metric-val">${headersList.length} Headers</div>
      </div>
    </section>

    <div class="filter-bar">
      <input type="text" id="searchInput" class="search-input" placeholder="Filter headers by key or value (e.g. 'cf-', 'user-agent')...">
      <span id="matchCount" style="font-size: 0.8rem; color: var(--text-muted);">${headersList.length} of ${headersList.length} displayed</span>
    </div>

    <div class="table-container">
      <table>
        <thead>
          <tr>
            <th>Header Name</th>
            <th>Header Value</th>
          </tr>
        </thead>
        <tbody id="headersBody">
          ${tableRows}
        </tbody>
      </table>
    </div>

    <footer>
      Inspected at ${escapeHtml(nowUtc)} · TravelView Origin Server on OCI
    </footer>
  </div>

  <div id="toast">Copied JSON to clipboard!</div>

  <script>
    const rawJson = ${JSON.stringify(jsonPayload)};
    const copyBtn = document.getElementById('copyJsonBtn');
    const toast = document.getElementById('toast');
    const searchInput = document.getElementById('searchInput');
    const rows = document.querySelectorAll('.header-row');
    const matchCount = document.getElementById('matchCount');
    const totalCount = rows.length;

    copyBtn.addEventListener('click', () => {
      navigator.clipboard.writeText(rawJson).then(() => {
        toast.classList.add('show');
        setTimeout(() => toast.classList.remove('show'), 2000);
      });
    });

    searchInput.addEventListener('input', (e) => {
      const q = e.target.value.toLowerCase().trim();
      let visible = 0;
      rows.forEach(row => {
        const key = row.getAttribute('data-key') || '';
        const val = row.getAttribute('data-value') || '';
        if (!q || key.includes(q) || val.includes(q)) {
          row.style.display = '';
          visible++;
        } else {
          row.style.display = 'none';
        }
      });
      matchCount.textContent = visible + ' of ' + totalCount + ' displayed';
    });
  </script>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store, no-cache, must-revalidate, proxy-revalidate',
    },
  });
}
