# TravelView Cloudflare Access assignment Worker

This Worker handles only the HTTPS path prefix tunnel.yourtravelview.com/secure:

- GET /secure reads the authenticated email from Cloudflare Access, adds the UTC request time and Cloudflare visitor country, and returns HTML.
- The country code links to /secure/{COUNTRY}.
- GET /secure/{COUNTRY} reads that country's SVG from the private travelview-private-flags R2 bucket and responds as image/svg+xml.
- No public R2 development URL or workers.dev URL is enabled. The existing hostname/path Cloudflare Access application remains the front door for the protected paths.

The source and deploy configuration belong in the public TravelView Git repository. The R2 bucket contents remain private and are read through the Worker binding.

## One-time setup

From this directory, run:

    npm install
    npx wrangler login
    npx wrangler whoami
    npx wrangler r2 bucket create travelview-private-flags

The R2 bucket is private by default. Do not enable its public development URL or attach a public custom domain.

Upload the SVG assets from the MIT-licensed flag-icons package into the private bucket:

    npm run upload-flags

The upload script stores objects as flags/US.svg, flags/CN.svg, and so on, with image/svg+xml metadata. It explicitly uses Wrangler's `--remote` option so objects are uploaded to the Cloudflare R2 bucket, not Wrangler's local development store. It also uploads a neutral XX.svg fallback for requests where Cloudflare does not provide a standard two-letter country code. The Worker validates the country code before looking up an object. If a supported flag is unexpectedly absent, it returns a 404 instead of exposing a bucket URL. The flag-icons MIT notice is included in LICENSES/flag-icons-MIT.txt.

## Local test

Run the Worker unit tests without Cloudflare credentials:

    npm test

The tests cover the HTML identity response, country link, private R2 object lookup and SVG MIME type, unauthenticated rejection, and HEAD behavior. Because the identity is supplied by Cloudflare Access in production, verify the actual identity in the browser after deployment.

## Deploy

After confirming the local behavior:

    npx wrangler deploy

The Wrangler route attaches the Worker to the existing proxied Tunnel hostname. Cloudflare Access evaluates the request before the Worker executes. Do not add a broad tunnel.yourtravelview.com/* Worker route: other TravelView pages should continue to reach the origin through the Tunnel.

## Production verification

1. In a private/incognito browser, open https://tunnel.yourtravelview.com/secure. It should redirect to Cloudflare Access login.
2. Sign in with the allowed Google identity. The Worker response should show the actual authenticated email, request time, and country link.
3. Click the country link. The browser should display the corresponding SVG flag. In Developer Tools → Network → select the country request → Headers, verify Content-Type: image/svg+xml; charset=utf-8.
4. Confirm a request to https://tunnel.yourtravelview.com/secure/XX returns 404 when no XX.svg object exists.

The route requires the existing DNS record for tunnel.yourtravelview.com to remain proxied and the existing Access application to cover both /secure and /secure/*.
