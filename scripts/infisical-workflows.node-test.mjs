// The composite action and every caller use a scoped read-only service token.
// Run: node --test scripts/infisical-workflows.node-test.mjs
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const GITHUB = join(ROOT, ".github");

function walkYml(dir, acc = []) {
  for (const ent of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, ent.name);
    if (ent.isDirectory()) walkYml(p, acc);
    else if (/\.ya?ml$/.test(ent.name)) acc.push(p);
  }
  return acc;
}

function infisicalSteps(yaml) {
  const lines = yaml.split("\n");
  const steps = [];
  for (let i = 0; i < lines.length; i++) {
    if (!/^\s+uses:\s+\.\/\.github\/actions\/infisical-secrets\s*$/.test(lines[i])) continue;
    let j = i + 1;
    for (; j < lines.length; j++) {
      if (/^\s+- (?:name|uses):/.test(lines[j])) break;
      if (/^\S/.test(lines[j])) break;
    }
    steps.push(lines.slice(i, j).join("\n"));
    i = j - 1;
  }
  return steps;
}

function expectedToken(block) {
  const path = (block.match(/^\s+secret-path:\s*(\S+)\s*$/m) || [])[1] || "/";
  const project = (block.match(/project-id:\s*\$\{\{\s*secrets\.([A-Z0-9_]+)\s*\}\}/) || [])[1];
  if (path === "/mac-certs") return "INFISICAL_MAC_CERTS_READ_TOKEN";
  if (path === "/asc") return "INFISICAL_ASC_READ_TOKEN";
  if (project === "INFISICAL_PROJECT_ID" && path === "/") return "INFISICAL_CONTACTLOGO_READ_TOKEN";
  return null;
}

test("composite action declares service-token and not client-id", () => {
  const action = readFileSync(join(GITHUB, "actions/infisical-secrets/action.yml"), "utf8");
  assert.match(action, /^  service-token:/m);
  assert.match(action, /INFISICAL_SERVICE_TOKEN: \$\{\{ inputs\.service-token \}\}/);
  assert.match(action, /^  asc-mode:/m);
  assert.doesNotMatch(action, /client-id:/);
  assert.doesNotMatch(action, /client-secret:/);
  assert.doesNotMatch(action, /INFISICAL_CLIENT_ID|INFISICAL_CLIENT_SECRET|INFISICAL_UNIVERSAL_AUTH_CLIENT/);
});

test("every infisical-secrets step uses the scoped token for its folder", () => {
  const files = readdirSync(join(GITHUB, "workflows"))
    .filter((name) => name.endsWith(".yml"))
    .map((name) => join(GITHUB, "workflows", name));
  let count = 0;
  for (const file of files) {
    const steps = infisicalSteps(readFileSync(file, "utf8"));
    for (const block of steps) {
      count += 1;
      assert.doesNotMatch(block, /client-id:|client-secret:/, file);
      const token = expectedToken(block);
      assert.ok(token, `unmapped step in ${file}:\n${block}`);
      assert.match(
        block,
        new RegExp(`service-token:\\s+\\$\\{\\{\\s*secrets\\.${token}\\s*\\}\\}`),
        `${file} expected ${token}`,
      );
    }
  }
  assert.equal(count, 11);
});

test("mac-release asc-mode stages the key and TestFlight lanes stay plain", () => {
  const mac = readFileSync(join(GITHUB, "workflows/mac-release.yml"), "utf8");
  const asc = infisicalSteps(mac).find((block) => /secret-path:\s*\/asc/.test(block));
  assert.ok(asc);
  assert.match(asc, /asc-mode:\s*"true"/);
  assert.doesNotMatch(mac, /GH_FALLBACK_ASC_/);

  for (const name of ["testflight.yml", "ios-testflight.yml", "mac-testflight.yml"]) {
    const yaml = readFileSync(join(GITHUB, "workflows", name), "utf8");
    const ascSteps = infisicalSteps(yaml).filter((block) => /secret-path:\s*\/asc/.test(block));
    assert.ok(ascSteps.length >= 1, name);
    for (const block of ascSteps) {
      assert.doesNotMatch(block, /asc-mode:/, `${name} stays in plain mode`);
    }
    assert.match(yaml, /GH_FALLBACK_ASC_KEY_P8:/);
  }
});

test("github workflows keep universal-auth only in vercel-catch-up", () => {
  for (const file of walkYml(GITHUB)) {
    if (file.endsWith(`${join("workflows", "vercel-catch-up.yml")}`)) continue;
    const text = readFileSync(file, "utf8");
    assert.doesNotMatch(text, /client-id:/, file);
    assert.doesNotMatch(text, /INFISICAL_UNIVERSAL_AUTH_CLIENT/, file);
    assert.doesNotMatch(text, /INFISICAL_CLIENT_SECRET/, file);
  }
  const catchUp = readFileSync(join(GITHUB, "workflows/vercel-catch-up.yml"), "utf8");
  assert.match(catchUp, /INFISICAL_CLIENT_ID:/);
  assert.match(catchUp, /INFISICAL_CLIENT_SECRET:/);
  assert.doesNotMatch(catchUp, /INFISICAL_SERVICE_TOKEN/);
  assert.match(catchUp, /node scripts\/infisical-fetch\.mjs/);
});
