// Contract test for `asc-api.mjs plan-release-build` (and its original name
// `next-shared-build`) plus `max-build`, against a stub App Store Connect
// (see ./stub-asc-fetch.mjs, loaded via `node --import`).  Fully offline:  a
// throwaway key is generated here, fetch never leaves the process, and every
// requested URL is asserted from the stub's call log.
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
const STAMP = "202610290000";

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

test("prints the merge stamp when the inventory sits below it", async () => {
  const expected = nextSharedBuild({
    iosBuilds: ["1200"],
    macBuilds: ["1300"],
    extraFloors: [1400],
    complete: true,
    mergeStamp: STAMP
  });
  assert.equal(expected.build, STAMP);
  const res = await runClient(
    ["plan-release-build", "com.example.solo", "1400", "--merge-stamp", STAMP],
    "single"
  );
  assert.equal(res.code, 0);
  assert.equal(res.stdout, expected.build);
  assert.match(res.stderr, /1 iOS build\(s\) \+ 1 macOS build\(s\) inspected/);
  assert.match(res.stderr, new RegExp(`merge stamp ${STAMP}`));
});

test("next-shared-build is the same command under its original name", async () => {
  const res = await runClient(
    ["next-shared-build", "com.example.solo", "1400", "--merge-stamp", STAMP],
    "single"
  );
  assert.equal(res.code, 0);
  assert.equal(res.stdout, STAMP);
});

test("collects both platforms of both apps when paired", async () => {
  const expected = nextSharedBuild({
    iosBuilds: ["1200", "1500"],
    macBuilds: ["1100", "1300"],
    extraFloors: [1400],
    complete: true,
    mergeStamp: STAMP
  });
  // The max (1500) sits in the PAIRED app's iOS list:  a client that only
  // reads the paired app's macOS builds still answers the stamp here, so the
  // call log below (not the value) pins the four inventories.
  assert.equal(expected.build, STAMP);
  const res = await runClient(
    ["plan-release-build", "com.example.wl", "com.example.wl.mac", "1400", "--merge-stamp", STAMP],
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

test("an existing build at or above the stamp moves one up", async () => {
  const res = await runClient(
    ["plan-release-build", "com.example.big", "--merge-stamp", STAMP],
    "single"
  );
  assert.equal(res.code, 0);
  assert.equal(res.stdout, "209912312360");
});

test("single app without a paired bundle id stays on one app", async () => {
  const res = await runClient(
    ["plan-release-build", "com.example.solo", "--merge-stamp", STAMP],
    "single"
  );
  assert.equal(res.code, 0);
  assert.equal(res.stdout, STAMP);
  assert.ok(!res.calls.some((url) => url.includes("filter[app]=app-wl")),
    "never queries another app");
});

test("a missing or malformed merge stamp exits 2 with no build", async () => {
  const missing = await runClient(["plan-release-build", "com.example.solo"], "single");
  assert.equal(missing.code, 2);
  assert.match(missing.stderr, /--merge-stamp <S> is required/);
  assert.equal(missing.stdout, "");
  for (const bad of ["999", "022610290000", "2026102900000"]) {
    const res = await runClient(
      ["plan-release-build", "com.example.solo", "--merge-stamp", bad],
      "single"
    );
    assert.equal(res.code, 2, bad);
    assert.match(res.stderr, /--merge-stamp <S> is required/, bad);
    assert.equal(res.stdout, "", `${bad} prints no build`);
  }
});

test("malformed pagination exits 2", async () => {
  for (const scenario of ["links-string", "links-next-number", "links-next-object", "links-null"]) {
    const res = await runClient(
      ["plan-release-build", "com.example.solo", "--merge-stamp", STAMP],
      scenario
    );
    assert.equal(res.code, 2, scenario);
    assert.match(res.stderr, /plan-release-build: malformed pagination/, scenario);
    assert.equal(res.stdout, "", `${scenario} prints no build`);
  }
});

test("null next link is the last page, not malformed", async () => {
  const res = await runClient(
    ["plan-release-build", "com.example.solo", "--merge-stamp", STAMP],
    "links-next-null"
  );
  assert.equal(res.code, 0);
  assert.equal(res.stdout, STAMP);
});

test("max-build prints one app record on one platform", async () => {
  const ios = await runClient(["max-build", "com.example.wl", "IOS"], "paired");
  assert.equal(ios.code, 0);
  assert.equal(ios.stdout, "1200");
  const mac = await runClient(["max-build", "com.example.wl", "MAC_OS"], "paired");
  assert.equal(mac.code, 0);
  assert.equal(mac.stdout, "1100");
  const big = await runClient(["max-build", "com.example.big", "IOS"], "single");
  assert.equal(big.code, 0);
  assert.equal(big.stdout, "209912312359");
  const empty = await runClient(["max-build", "com.example.big", "MAC_OS"], "single");
  assert.equal(empty.code, 0);
  assert.equal(empty.stdout, "0");
});

test("max-build fails closed on an unknown app or platform", async () => {
  const unknown = await runClient(["max-build", "com.example.nobody", "IOS"], "single");
  assert.equal(unknown.code, 2);
  assert.equal(unknown.stdout, "");
  const platform = await runClient(["max-build", "com.example.wl", "TVOS"], "paired");
  assert.equal(platform.code, 2);
  assert.equal(platform.stdout, "");
});
