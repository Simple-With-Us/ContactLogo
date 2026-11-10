import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const ROOT = join(dirname(fileURLToPath(import.meta.url)));
const mjs = readFileSync(join(ROOT, "asc-api.mjs"), "utf8");
const branch = mjs.slice(mjs.indexOf('method === "ensure-tf-ready"'));

test("post-sync recheck uses a short default budget and faster polls", () => {
  assert.match(branch, /const recheck = String\(process\.env\.IOS_TF_READY_RECHECK/);
  assert.match(branch, /return recheck \? 90 : 900/);
  assert.match(branch, /const POLL_MS = recheck \? 5000 : 15000/);
  assert.match(branch, /recheck mode/);
});

test("post-sync recheck skips compliance patch and What to Test", () => {
  assert.match(branch, /if \(!recheck && enc !== false\)/);
  assert.match(branch, /if \(!recheck\) \{[\s\S]*setWhatToTest/);
});
