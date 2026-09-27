import { headers } from 'next/headers';

export const dynamic = 'force-dynamic';

export const metadata = {
  title: 'Cloudflare Access validation | TravelView',
  robots: { index: false, follow: false },
};

/** Visible origin page for demonstrating the Cloudflare Access login result. */
export default async function SecurePage() {
  const requestHeaders = await headers();
  const email = requestHeaders.get('cf-access-authenticated-user-email');
  const country = requestHeaders.get('cf-ipcountry');
  const rayId = requestHeaders.get('cf-ray');
  const checkedAt = new Date().toISOString();

  return (
    <main className="min-h-[70vh] px-6 py-16 text-paper">
      <section className="mx-auto max-w-2xl rounded-2xl border border-white/10 bg-white/[.03] p-8 shadow-xl">
        <p className="text-xs font-semibold uppercase tracking-[.18em] text-accentBright">
          Cloudflare Zero Trust · Access validation
        </p>
        <h1 className="mt-4 text-3xl font-semibold tracking-tight">
          Access granted
        </h1>
        <p className="mt-3 leading-relaxed text-muted">
          Cloudflare Access evaluated this request and forwarded the authenticated
          identity to the TravelView origin.
        </p>

        <dl className="mt-8 divide-y divide-white/10 rounded-xl border border-white/10">
          <InfoRow label="Authenticated email">
            {email ?? 'No Access identity header received'}
          </InfoRow>
          <InfoRow label="Visitor country">
            {country && country !== 'XX' ? country : 'Not available'}
          </InfoRow>
          <InfoRow label="Verified at (UTC)">{checkedAt}</InfoRow>
          <InfoRow label="Cloudflare Ray ID">{rayId ?? 'Not available'}</InfoRow>
        </dl>

        {!email && (
          <p role="status" className="mt-5 rounded-lg border border-amber-400/30 bg-amber-400/10 p-4 text-sm text-amber-100">
            The page loaded without an Access identity header. Check that this URL
            is covered by the Access application and that the request passed through
            Cloudflare Access.
          </p>
        )}

        <p className="mt-6 text-xs leading-relaxed text-muted">
          This is an assignment diagnostic page. A production service should validate
          the Cloudflare Access JWT before using identity claims for authorization.
        </p>
      </section>
    </main>
  );
}

function InfoRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="grid gap-1 px-4 py-3 sm:grid-cols-[11rem_1fr] sm:gap-4">
      <dt className="text-sm text-muted">{label}</dt>
      <dd className="break-all font-mono text-sm">{children}</dd>
    </div>
  );
}
