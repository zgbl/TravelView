const HTML_HEADERS = {
  "content-type": "text/html; charset=utf-8",
  "cache-control": "private, no-store",
  "x-content-type-options": "nosniff",
  "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'",
};

const SVG_HEADERS = {
  "content-type": "image/svg+xml; charset=utf-8",
  "cache-control": "private, no-store",
  "x-content-type-options": "nosniff",
  "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; sandbox",
};

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (character) => {
    const entities = {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    };
    return entities[character];
  });
}

function htmlPage(email, timestamp, country) {
  const countryUrl =
    "https://tunnel.yourtravelview.com/secure/" +
    encodeURIComponent(country);
  const safeEmail = escapeHtml(email);
  const safeTimestamp = escapeHtml(timestamp);
  const safeCountry = escapeHtml(country);

  return (
    "<!doctype html>\n" +
    '<html lang="en">\n' +
    "  <head>\n" +
    '    <meta charset="utf-8">\n' +
    '    <meta name="viewport" content="width=device-width, initial-scale=1">\n' +
    "    <title>Cloudflare Access identity</title>\n" +
    "    <style>\n" +
    "      body { font: 16px/1.6 system-ui, sans-serif; max-width: 48rem; margin: 4rem auto; padding: 0 1.25rem; color: #172033; }\n" +
    "      main { border: 1px solid #ccd3df; border-radius: 1rem; padding: 2rem; }\n" +
    "      h1 { margin-top: 0; }\n" +
    "      a { color: #0759c7; }\n" +
    "      code, time { overflow-wrap: anywhere; }\n" +
    "    </style>\n" +
    "  </head>\n" +
    "  <body>\n" +
    "    <main>\n" +
    "      <h1>Cloudflare Worker identity</h1>\n" +
    "      <p>" +
    safeEmail +
    " authenticated at <time datetime=\"" +
    safeTimestamp +
    "\">" +
    safeTimestamp +
    "</time> from <a href=\"" +
    countryUrl +
    "\">" +
    safeCountry +
    "</a></p>\n" +
    "    </main>\n" +
    "  </body>\n" +
    "</html>"
  );
}

function errorResponse(message, status) {
  return new Response(message, {
    status,
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method !== "GET" && request.method !== "HEAD") {
      return errorResponse("Method not allowed", 405);
    }

    if (url.pathname === "/secure" || url.pathname === "/secure/") {
      const identity = ctx.access ? await ctx.access.getIdentity() : null;
      if (!identity?.email) {
        return errorResponse(
          "Cloudflare Access authentication is required",
          401,
        );
      }

      const countryValue = request.cf?.country ?? "XX";
      const country = /^[A-Z]{2}$/.test(countryValue) ? countryValue : "XX";
      const timestamp = new Date().toISOString();

      return new Response(
        request.method === "HEAD"
          ? null
          : htmlPage(identity.email, timestamp, country),
        {
          headers: HTML_HEADERS,
        },
      );
    }

    const flagMatch = url.pathname.match(/^\/secure\/([A-Za-z]{2})\/?$/);
    if (flagMatch) {
      const country = flagMatch[1].toUpperCase();
      const flag = await env.FLAGS.get("flags/" + country + ".svg");
      if (!flag) {
        return errorResponse(
          "No flag asset is stored for country code " + country,
          404,
        );
      }

      return new Response(request.method === "HEAD" ? null : flag.body, {
        headers: SVG_HEADERS,
      });
    }

    return errorResponse("Not found", 404);
  },
};
