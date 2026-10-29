// Contract test for `asc-api.mjs next-shared-build` against a stub App Store
// Connect (see ./stub-asc-fetch.mjs, loaded via `node --import`).  Fully
// offline:  a throwaway key is generated here, fetch never leaves the
// process, and every requested URL is asserted from the stub's call log.
import assert from "node:assert/strict";
import test from "node:test";
import { execFile } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import { nextSharedBuild } from "./shared-build.mjs";

const execFileAsync = promisify(execFile);
const here = dirname(fileURLToPath(import.meta.url));

// A throwaway key pair, generated here and never committed.  The client
// parses a PEM before it accepts it, so a fake envelope is not a key.
const pem = generateKeyPairSync("ec", { namedCurve: "prime256v1" })
  .privateKey.export({ type: "pkcs8", format: "pem" });

async function runClient(args, scenario) {
  const dir = mkdtempSync(join(tmpdir(), "nsb-"));
  const log = join(dir, "calls.log");
  const env = { ...process.env };
  delete env.APPLE_API_KEY_ID;
  delete env.APPLE_API_ISSUER_ID;
  delete env.APPLE_API_KEY_P8_BASE64;
  delete env.ASC_APPLE_ID;
  env.ASC_KEY_ID = "TESTKEY001";
  env.ASC_ISSUER_ID = "test-issuer";
  env.ASC_KEY_P8 = pem;
  env.STUB_ASC_SCENARIO = scenario;
  env.STUB_ASC_LOG = log;
  try {
    const { stdout, stderr } = await execFileAsync(
      process.execPath,
      ["--import", join(here, "stub-asc-fetch.mjs"), join(here, "asc-api.mjs"), ...args],
      { env }
    );
    return { code: 0, stdout: stdout.trim(), stderr, calls: readCalls(log) };
  } catch (err) {
    return {
      code: err.code,
      stdout: String(err.stdout || "").trim(),
      stderr: String(err.stderr || ""),
      calls: readCalls(log)
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function readCalls(log) {
  try {
    return readFileSync(log, "utf8").split("\n").filter(Boolean);
  } catch {
    return [];
  }
}

function buildsCall(calls, appId, platform) {
  return calls.some((url) =>
    url.includes("/v1/builds?") &&
    url.includes(`filter[app]=${appId}`) &&
    url.includes(`filter[preReleaseVersion.platform]=${platform}`));
}

test("prints nextSharedBuild over an iOS build, a macOS build and a floor", async () => {
  const expected = nextSharedBuild({
    iosBuilds: ["1200"],
    macBuilds: ["1300"],
    extraFloors: [1400],
    complete: true
  });
  const res = await runClient(["next-shared-build", "com.example.solo", "1400"], "single");
  assert.equal(res.code, 0);
  assert.equal(res.stdout, expected.build);
  assert.equal(res.stdout, "1401");
});

test("collects both platforms of both apps when paired", async () => {
  const expected = nextSharedBuild({
    iosBuilds: ["1200", "1500"],
    macBuilds: ["1100", "1300"],
    extraFloors: [1400],
    complete: true
  });
  // The max (1500) sits in the PAIRED app's iOS list:  a client that only
  // reads the paired app's macOS builds answers 1401, not 1501.
  assert.equal(expected.build, "1501");
  const res = await runClient(
    ["next-shared-build", "com.example.wl", "com.example.wl.mac", "1400"],
    "paired"
  );
  assert.equal(res.code, 0);
  assert.equal(res.stdout, expected.build);
  assert.match(res.stderr, /2 iOS build\(s\) \+ 2 macOS build\(s\) inspected/);
  assert.ok(buildsCall(res.calls, "app-wl", "IOS"), "reads IOS of the main app");
  assert.ok(buildsCall(res.calls, "app-wl", "MAC_OS"), "reads MAC_OS of the main app");
  assert.ok(buildsCall(res.calls, "app-wlmac", "IOS"), "reads IOS of the paired app");
  assert.ok(buildsCall(res.calls, "app-wlmac", "MAC_OS"), "reads MAC_OS of the paired app");
});

test("single app without a paired bundle id stays on one app", async () => {
  const res = await runClient(["next-shared-build", "com.example.solo"], "single");
  assert.equal(res.code, 0);
  assert.equal(res.stdout, "1301");
  assert.ok(!res.calls.some((url) => url.includes("filter[app]=app-wl")),
    "never queries another app");
});

test("malformed pagination exits 2", async () => {
  for (const scenario of ["links-string", "links-next-number", "links-next-object", "links-null"]) {
    const res = await runClient(["next-shared-build", "com.example.solo"], scenario);
    assert.equal(res.code, 2, scenario);
    assert.match(res.stderr, /next-shared-build: malformed pagination/, scenario);
    assert.equal(res.stdout, "", `${scenario} prints no build`);
  }
});

test("null next link is the last page, not malformed", async () => {
  const res = await runClient(["next-shared-build", "com.example.solo"], "links-next-null");
  assert.equal(res.code, 0);
  assert.equal(res.stdout, "1301");
});
