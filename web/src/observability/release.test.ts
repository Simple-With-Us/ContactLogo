import assert from "node:assert/strict";
import { test } from "node:test";
import { resolveSentryRelease } from "./release.ts";

test("falls back to Vercel then GitHub SHA", () => {
  assert.equal(
    resolveSentryRelease({ VERCEL_GIT_COMMIT_SHA: "deadbeef", GITHUB_SHA: "cccc" }),
    "deadbeef",
  );
  assert.equal(resolveSentryRelease({ GITHUB_SHA: "abcd1234" }), "abcd1234");
  assert.equal(resolveSentryRelease({}), "");
});
