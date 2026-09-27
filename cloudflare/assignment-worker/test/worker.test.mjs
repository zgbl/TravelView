import test from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";

function makeContext(email = "owner@example.com") {
  return email
    ? { access: { async getIdentity() { return { email }; } } }
    : {};
}

function makeEnv(objects = {}) {
  return {
    FLAGS: {
      async get(key) {
        if (!(key in objects)) return null;
        return { body: new Response(objects[key]).body };
      },
    },
  };
}

test("GET /secure returns HTML with the authenticated identity, timestamp, and country link", async () => {
  const request = new Request("https://tunnel.yourtravelview.com/secure");
  Object.defineProperty(request, "cf", { value: { country: "US" } });
  const response = await worker.fetch(request, makeEnv(), makeContext());
  const body = await response.text();

  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type"), /^text\/html; charset=utf-8$/);
  assert.match(body, /owner@example\.com authenticated at/);
  assert.match(body, /<time datetime="\d{4}-\d{2}-\d{2}T[^"]+Z">/);
  assert.match(body, /href="https:\/\/tunnel\.yourtravelview\.com\/secure\/US">US<\/a>/);
});

test("GET /secure/{COUNTRY} reads the private R2 object and returns SVG content type", async () => {
  let requestedKey;
  const env = {
    FLAGS: {
      async get(key) {
        requestedKey = key;
        return { body: new Response("<svg></svg>").body };
      },
    },
  };

  const response = await worker.fetch(
    new Request("https://tunnel.yourtravelview.com/secure/us"),
    env,
    makeContext(),
  );

  assert.equal(requestedKey, "flags/US.svg");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type"), /^image\/svg\+xml; charset=utf-8$/);
  assert.equal(await response.text(), "<svg></svg>");
});

test("GET /secure rejects requests without an Access-authenticated identity", async () => {
  const response = await worker.fetch(
    new Request("https://tunnel.yourtravelview.com/secure"),
    makeEnv(),
    makeContext(null),
  );

  assert.equal(response.status, 401);
});

test("unknown country codes use the private XX fallback asset", async () => {
  const request = new Request("https://tunnel.yourtravelview.com/secure");
  Object.defineProperty(request, "cf", { value: { country: "T1" } });
  const response = await worker.fetch(request, makeEnv(), makeContext());
  const body = await response.text();

  assert.match(body, /\/secure\/XX/);
});

test("HEAD returns headers without a response body", async () => {
  const response = await worker.fetch(
    new Request("https://tunnel.yourtravelview.com/secure", { method: "HEAD" }),
    makeEnv(),
    makeContext(),
  );

  assert.equal(response.status, 200);
  assert.equal(await response.text(), "");
});

test("country route returns 404 for missing flag objects", async () => {
  const response = await worker.fetch(
    new Request("https://tunnel.yourtravelview.com/secure/ZZ"),
    makeEnv(),
    makeContext(),
  );

  assert.equal(response.status, 404);
  assert.match(await response.text(), /ZZ/);
});
