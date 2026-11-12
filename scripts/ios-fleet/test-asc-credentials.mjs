// AFC-359: asc-api.mjs resolves App Store Connect credentials from the environment first,
// then from Infisical through fleet-secrets, and keeps the key id and private key together.
// Runs asc-api.mjs against a local HTTP server with a FAKE fleet-secrets binary and a
// throwaway HOME.  The JWT header's kid proves which key id was used.  No real secrets.
//
// 2026-10-21 (AFC-459): a path on disk is not a credential source.  ASC_KEY_PATH is
// ignored wherever it appears, and the key comes from the environment or from
// fleet-secrets.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { chmodSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { createServer } from "node:http";
import { generateKeyPairSync } from "node:crypto";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const here = dirname(fileURLToPath(import.meta.url));
const script = join(here, "asc-api.mjs");
const pem = () => generateKeyPairSync("ec", { namedCurve: "prime256v1" }).privateKey
  .export({ type: "pkcs8", format: "pem" });

const root = mkdtempSync(join(tmpdir(), "asc-js-test-"));
const home = join(root, "home");
mkdirSync(home);
const ascPem = pem();
const otherPem = pem();
const fake = join(root, "fleet-secrets");
writeFileSync(fake, `#!/usr/bin/env node
const [, , verb, name, , folder] = process.argv;
const table = {
  "/asc:ASC_KEY_ID": "ASCKEY0001",
  "/asc:ASC_ISSUER_ID": "issuer-from-asc",
  "/asc:ASC_KEY_P8": ${JSON.stringify(ascPem)},
  "/authkey-otherkey01-p8:AUTHKEY_OTHERKEY01": ${JSON.stringify(otherPem)},
};
const v = verb === "get" ? table[folder + ":" + name] : undefined;
if (v === undefined) process.exit(3);
process.stdout.write(v + "\\n");
`);
chmodSync(fake, 0o755);

function run(env) {
  return new Promise((resolve) => {
    const seen = [];
    const server = createServer((req, res) => {
      seen.push(req.headers.authorization || "");
      res.setHeader("content-type", "application/json");
      res.end("{\"data\":[]}");
    });
    server.listen(0, "127.0.0.1", () => {
      const url = `http://127.0.0.1:${server.address().port}/v1/apps`;
      const base = { PATH: process.env.PATH, HOME: home, FLEET_SECRETS: fake };
      const child = spawn(process.execPath, [script, "GET", url], { env: { ...base, ...env }, stdio: ["ignore", "pipe", "pipe"] });
      child.stdout.resume();
      let stderr = "";
      child.stderr.on("data", (d) => { stderr += d; });
      child.on("close", (code) => {
        server.close();
        const jwt = (seen[0] || "").replace(/^Bearer /, "");
        let kid = null;
        let iss = null;
        if (jwt) {
          const part = (i) => JSON.parse(Buffer.from(jwt.split(".")[i], "base64url").toString());
          kid = part(0).kid;
          iss = part(1).iss;
        }
        resolve({ code, kid, iss, stderr });
      });
    });
  });
}

test("nothing in the environment:  id, issuer and key all come from /asc", async () => {
  const r = await run({});
  assert.equal(r.code, 0);
  assert.equal(r.kid, "ASCKEY0001");
  assert.equal(r.iss, "issuer-from-asc");
});

test("an env key id equal to the /asc one is served from /asc", async () => {
  const r = await run({ ASC_KEY_ID: "ASCKEY0001" });
  assert.equal(r.code, 0);
  assert.equal(r.kid, "ASCKEY0001");
});

test("an env key id that is not the /asc one gets its own .p8, never the /asc key", async () => {
  const r = await run({ ASC_KEY_ID: "OTHERKEY01", ASC_ISSUER_ID: "issuer-for-other" });
  assert.equal(r.code, 0);
  assert.equal(r.kid, "OTHERKEY01");
  // The /asc issuer belongs to the /asc key id, never to this one.
  assert.equal(r.iss, "issuer-for-other");
});

test("an env key id that is not the /asc one and no issuer of its own fails closed", async () => {
  // Otherwise the JWT would be signed by the per-key .p8 while claiming the /asc issuer.
  const r = await run({ ASC_KEY_ID: "OTHERKEY01" });
  assert.notEqual(r.code, 0);
  assert.equal(r.kid, null);
});

test("an env key id with no key material anywhere fails closed", async () => {
  const r = await run({ ASC_KEY_ID: "NOSUCHKEY0" });
  assert.notEqual(r.code, 0);
  assert.equal(r.kid, null);
});

test("a complete environment (id, issuer, ASC_KEY_P8) wins and never calls fleet-secrets", async () => {
  const r = await run({ ASC_KEY_ID: "ENVKEY0001", ASC_ISSUER_ID: "env-issuer", ASC_KEY_P8: pem(), FLEET_SECRETS: join(root, "does-not-exist") });
  assert.equal(r.code, 0);
  assert.equal(r.kid, "ENVKEY0001");
  assert.equal(r.iss, "env-issuer");
  assert.match(r.stderr, /asc-auth: using ASC_KEY_P8 environment/);
});

test("the APPLE_API_* trio wins over the ASC_* environment", async () => {
  const r = await run({
    APPLE_API_KEY_ID: "APPLEKEY01",
    APPLE_API_ISSUER_ID: "apple-issuer",
    APPLE_API_KEY_P8_BASE64: Buffer.from(pem(), "utf8").toString("base64"),
    ASC_KEY_ID: "ENVKEY0001",
    ASC_ISSUER_ID: "env-issuer",
    ASC_KEY_P8: pem()
  });
  assert.equal(r.code, 0);
  assert.equal(r.kid, "APPLEKEY01");
  assert.equal(r.iss, "apple-issuer");
});

test("an ASC_KEY_P8 that is not a private key is refused as a credential error", async () => {
  // A truncated key reaches the signer as a stack trace otherwise.
  const r = await run({ ASC_KEY_ID: "ENVKEY0001", ASC_ISSUER_ID: "env-issuer", ASC_KEY_P8: "not a private key" });
  assert.notEqual(r.code, 0);
  assert.equal(r.kid, null);
  assert.match(r.stderr, /ASC_KEY_P8 is set but is not a PEM private key/);
});

test("a named ASC_KEY_PATH is ignored:  the credential comes from /asc", async () => {
  // A path on disk is not an approved credential source (AFC-459), so the file
  // never decides which key signs the request.
  const keyFile = join(root, "named-key.p8");
  writeFileSync(keyFile, pem());
  const r = await run({ ASC_KEY_PATH: keyFile });
  assert.equal(r.code, 0);
  assert.equal(r.kid, "ASCKEY0001");
  assert.equal(r.iss, "issuer-from-asc");
  assert.doesNotMatch(r.stderr, /ASC_KEY_PATH/);
});

test.after(() => rmSync(root, { recursive: true, force: true }));
