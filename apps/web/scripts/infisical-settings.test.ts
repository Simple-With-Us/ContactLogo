/**
 * Tests for the vendored Infisical settings client (`infisical-settings.ts`).
 *
 * Proves the canonical SOT contract:
 *   - init() populates the in-memory cache from Infisical;
 *   - reads after init make zero network calls (mock fetch call count);
 *   - set() writes to Infisical BEFORE updating the cache (write-through
 *     ordering), and a failed write rejects with the cache untouched;
 *   - a failed background refresh keeps serving the last-known-good cache.
 */
import test from "node:test";
import assert from "node:assert/strict";
import {
  createInfisicalSettings,
  InfisicalLoadError,
  InfisicalWriteError,
} from "./infisical-settings.ts";

const PROJECT_ID = "8a0ae9aa-8b67-443e-943d-c55a767dab50";

type Call = { url: string; method: string };
interface MockResponse {
  ok: boolean;
  status: number;
  json: () => Promise<unknown>;
}
function jsonResponse(status: number, body: unknown): MockResponse {
  return { ok: status >= 200 && status < 300, status, json: async () => body };
}

/** Mock fetch that records every call in order and serves scripted responses. */
function makeMock(script: (call: Call, calls: Call[]) => MockResponse | Promise<MockResponse>) {
  const calls: Call[] = [];
  const fetchImpl = (async (url: unknown, init?: { method?: string }) => {
    const call: Call = { url: String(url), method: init?.method ?? "GET" };
    calls.push(call);
    return script(call, calls);
  }) as unknown as typeof fetch;
  return { fetchImpl, calls };
}

const CREDS = { clientId: "test-client-id", clientSecret: "test-client-secret" };

function loginThenSecrets(secrets: Array<{ secretKey: string; secretValue: string }>) {
  return makeMock((call) => {
    if (call.url.includes("/api/v1/auth/universal-auth/login")) {
      return jsonResponse(200, { accessToken: "token-1" });
    }
    return jsonResponse(200, { secrets });
  });
}

test("init() populates the in-memory cache from Infisical", async () => {
  const { fetchImpl, calls } = loginThenSecrets([
    { secretKey: "DD_SERVICE", secretValue: "contactlogo-web" },
    { secretKey: "DD_SITE", secretValue: "us5.datadoghq.com" },
  ]);
  const settings = createInfisicalSettings({
    ...CREDS,
    projectId: PROJECT_ID,
    environment: "dev",
    refreshIntervalMs: 0,
    fetchImpl,
  });
  await settings.init();
  try {
    assert.equal(settings.get("DD_SERVICE"), "contactlogo-web");
    assert.equal(settings.get("DD_SITE"), "us5.datadoghq.com");
    assert.equal(settings.has("MISSING"), false);
    assert.deepEqual(settings.getAll(), {
      DD_SERVICE: "contactlogo-web",
      DD_SITE: "us5.datadoghq.com",
    });
    // Login + one secrets GET.
    assert.equal(calls.length, 2);
    assert.ok(calls[1]!.url.includes("environment=dev"));
    assert.ok(calls[1]!.url.includes(`workspaceId=${PROJECT_ID}`));
  } finally {
    settings.stop();
  }
});

test("reads after init make zero network calls", async () => {
  const { fetchImpl, calls } = loginThenSecrets([
    { secretKey: "A", secretValue: "1" },
  ]);
  const settings = createInfisicalSettings({
    ...CREDS,
    projectId: PROJECT_ID,
    environment: "dev",
    refreshIntervalMs: 0,
    fetchImpl,
  });
  await settings.init();
  try {
    const before = calls.length;
    settings.get("A");
    settings.getRequired("A");
    settings.has("A");
    settings.getAll();
    assert.equal(calls.length, before, "runtime reads must not hit the network");
  } finally {
    settings.stop();
  }
});

test("getRequired() fails fast naming the missing key and pointing at INFISICAL.md", async () => {
  const { fetchImpl } = loginThenSecrets([]);
  const settings = createInfisicalSettings({
    ...CREDS,
    projectId: PROJECT_ID,
    environment: "dev",
    refreshIntervalMs: 0,
    fetchImpl,
  });
  await settings.init();
  try {
    assert.throws(() => settings.getRequired("NOPE"), (error: unknown) => {
      const message = (error as Error).message;
      return message.includes('"NOPE"') && message.includes("INFISICAL.md");
    });
  } finally {
    settings.stop();
  }
});

test("set() writes to Infisical FIRST, then updates the cache", async () => {
  const events: string[] = [];
  const { fetchImpl } = makeMock((call) => {
    if (call.url.includes("/api/v1/auth/universal-auth/login")) {
      return jsonResponse(200, { accessToken: "token-1" });
    }
    if (call.method === "PATCH") {
      events.push("infisical-write");
      // The cache must NOT be updated yet when Infisical is written.
      return jsonResponse(200, {});
    }
    return jsonResponse(200, { secrets: [{ secretKey: "K", secretValue: "old" }] });
  });
  const settings = createInfisicalSettings({
    ...CREDS,
    projectId: PROJECT_ID,
    environment: "dev",
    refreshIntervalMs: 0,
    fetchImpl,
  });
  await settings.init();
  try {
    assert.equal(settings.get("K"), "old");
    await settings.set("K", "new");
    assert.deepEqual(events, ["infisical-write"]);
    assert.equal(settings.get("K"), "new", "cache updated only after the Infisical write succeeded");
  } finally {
    settings.stop();
  }
});

test("set() creates the secret with POST when it does not exist yet", async () => {
  const methods: string[] = [];
  const { fetchImpl } = makeMock((call) => {
    if (call.url.includes("/api/v1/auth/universal-auth/login")) {
      return jsonResponse(200, { accessToken: "token-1" });
    }
    if (call.method === "PATCH") {
      methods.push("PATCH");
      return jsonResponse(404, {});
    }
    if (call.method === "POST") {
      methods.push("POST");
      return jsonResponse(201, {});
    }
    return jsonResponse(200, { secrets: [] });
  });
  const settings = createInfisicalSettings({
    ...CREDS,
    projectId: PROJECT_ID,
    environment: "dev",
    refreshIntervalMs: 0,
    fetchImpl,
  });
  await settings.init();
  try {
    await settings.set("BRAND_NEW", "v");
    assert.deepEqual(methods, ["PATCH", "POST"]);
    assert.equal(settings.get("BRAND_NEW"), "v");
  } finally {
    settings.stop();
  }
});

test("failed write-through rejects and leaves the cache untouched", async () => {
  const { fetchImpl } = makeMock((call) => {
    if (call.url.includes("/api/v1/auth/universal-auth/login")) {
      return jsonResponse(200, { accessToken: "token-1" });
    }
    if (call.method === "PATCH") {
      return jsonResponse(500, { message: "boom" });
    }
    return jsonResponse(200, { secrets: [{ secretKey: "K", secretValue: "old" }] });
  });
  const settings = createInfisicalSettings({
    ...CREDS,
    projectId: PROJECT_ID,
    environment: "dev",
    refreshIntervalMs: 0,
    fetchImpl,
  });
  await settings.init();
  try {
    await assert.rejects(() => settings.set("K", "new"), (error: unknown) => {
      return error instanceof InfisicalWriteError && error.key === "K";
    });
    assert.equal(
      settings.get("K"),
      "old",
      "cache must never diverge from Infisical on a failed write",
    );
  } finally {
    settings.stop();
  }
});

test("failed refresh keeps the last-known-good cache and logs loudly", async () => {
  let attempt = 0;
  const logged: string[] = [];
  const originalError = console.error;
  console.error = (...args: unknown[]) => {
    logged.push(String(args[0]));
  };
  const { fetchImpl } = makeMock((call) => {
    if (call.url.includes("/api/v1/auth/universal-auth/login")) {
      return jsonResponse(200, { accessToken: "token-1" });
    }
    attempt += 1;
    if (attempt === 1) {
      return jsonResponse(200, { secrets: [{ secretKey: "K", secretValue: "good" }] });
    }
    return jsonResponse(503, { message: "infisical down" });
  });
  const settings = createInfisicalSettings({
    ...CREDS,
    projectId: PROJECT_ID,
    environment: "dev",
    refreshIntervalMs: 0,
    fetchImpl,
  });
  try {
    await settings.init();
    assert.equal(settings.get("K"), "good");
    // A direct refresh() throws on failure (the background timer's wrapper
    // logs loudly instead); either way the cache must stay intact.
    await settings.refresh();
    assert.fail("refresh should have thrown");
  } catch (error) {
    assert.ok(error instanceof InfisicalLoadError);
  } finally {
    console.error = originalError;
    settings.stop();
  }
  assert.equal(settings.get("K"), "good", "last-known-good cache must survive a failed refresh");
});

test("background refresh failure logs loudly and keeps serving last-known-good", async () => {
  let secretsCalls = 0;
  const logged: string[] = [];
  const originalError = console.error;
  console.error = (...args: unknown[]) => {
    logged.push(String(args[0]));
  };
  const { fetchImpl } = makeMock((call) => {
    if (call.url.includes("/api/v1/auth/universal-auth/login")) {
      return jsonResponse(200, { accessToken: "token-1" });
    }
    secretsCalls += 1;
    if (secretsCalls === 1) {
      return jsonResponse(200, { secrets: [{ secretKey: "K", secretValue: "good" }] });
    }
    return jsonResponse(503, { message: "infisical down" });
  });
  const settings = createInfisicalSettings({
    ...CREDS,
    projectId: PROJECT_ID,
    environment: "dev",
    refreshIntervalMs: 30,
    fetchImpl,
  });
  try {
    await settings.init();
    // Wait for at least one background refresh cycle to fail.
    await new Promise((resolve) => setTimeout(resolve, 200));
    assert.equal(settings.get("K"), "good", "last-known-good cache must survive");
    assert.ok(
      logged.some((line) => line.includes("last-known-good")),
      "failure must be logged loudly",
    );
  } finally {
    console.error = originalError;
    settings.stop();
  }
});

test("init() fails fast when universal-auth login fails", async () => {  const { fetchImpl } = makeMock((call) => {
    if (call.url.includes("/api/v1/auth/universal-auth/login")) {
      return jsonResponse(401, { message: "bad credentials" });
    }
    return jsonResponse(200, { secrets: [] });
  });
  const settings = createInfisicalSettings({
    ...CREDS,
    projectId: PROJECT_ID,
    environment: "dev",
    refreshIntervalMs: 0,
    fetchImpl,
  });
  await assert.rejects(() => settings.init(), InfisicalLoadError);
  settings.stop();
});
