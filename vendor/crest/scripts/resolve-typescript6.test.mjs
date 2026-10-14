import assert from "node:assert/strict";
import { test } from "node:test";

test("eslint resolve hook maps typescript to the TS 6 JS API", async () => {
  await import("./resolve-typescript6.mjs");
  const ts = await import("typescript");
  assert.match(ts.version, /^6\./);
});
