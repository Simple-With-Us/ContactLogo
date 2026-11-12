// Test-only App Store Connect stub for asc-api.mjs, loaded via
// `node --import <this file>`.  Replaces global fetch before the client runs
// and answers the /v1/apps and /v1/builds reads plan-release-build makes.
// No network:  any other host throws, and every requested URL is appended to
// $STUB_ASC_LOG.  $STUB_ASC_SCENARIO varies the links shape of the builds
// pages ("paired" and "single" answer plain pages; "links-*" answers a
// malformed or null pager to pin the client's validation).
import { appendFileSync } from "node:fs";

const SCENARIO = process.env.STUB_ASC_SCENARIO || "paired";
const LOG = process.env.STUB_ASC_LOG || "";

const APPS = {
  "com.example.wl": "app-wl",
  "com.example.wl.mac": "app-wlmac",
  "com.example.solo": "app-solo",
  "com.example.big": "app-big"
};

// One static inventory; the scenario only changes the links shape.
const BUILDS = {
  "app-wl|IOS": ["1200"],
  "app-wl|MAC_OS": ["1100"],
  "app-wlmac|IOS": ["1500"],
  "app-wlmac|MAC_OS": ["1300"],
  "app-solo|IOS": ["1200"],
  "app-solo|MAC_OS": ["1300"],
  "app-big|IOS": ["209912312359"],
  "app-big|MAC_OS": []
};

function linksFor() {
  switch (SCENARIO) {
    case "links-string": return "oops";
    case "links-next-number": return { next: 42 };
    case "links-next-object": return { next: { href: "https://example.invalid/p2" } };
    case "links-null": return null;
    case "links-next-null": return { next: null };
    default: return {};
  }
}

function json(obj, status = 200) {
  const text = JSON.stringify(obj);
  return { ok: status >= 200 && status < 300, status, text: async () => text };
}

globalThis.fetch = async (url) => {
  const raw = String(url);
  if (LOG) appendFileSync(LOG, `${raw}\n`);
  const parsed = new URL(raw);
  if (parsed.hostname !== "api.appstoreconnect.apple.com") {
    throw new Error(`stub-asc-fetch: unexpected host ${parsed.hostname}`);
  }
  if (parsed.pathname === "/v1/apps" && parsed.searchParams.has("filter[bundleId]")) {
    const want = parsed.searchParams.get("filter[bundleId]");
    const id = APPS[want];
    return json(id
      ? { data: [{ id, attributes: { bundleId: want } }], links: {} }
      : { data: [], links: {} });
  }
  if (parsed.pathname === "/v1/builds") {
    const app = parsed.searchParams.get("filter[app]");
    const platform = parsed.searchParams.get("filter[preReleaseVersion.platform]");
    const versions = BUILDS[`${app}|${platform}`] || [];
    return json({
      data: versions.map((version, i) => ({
        id: `b-${app}-${platform}-${i}`,
        attributes: { version }
      })),
      links: linksFor()
    });
  }
  return json({ errors: [{ code: "NOT_FOUND" }] }, 404);
};
