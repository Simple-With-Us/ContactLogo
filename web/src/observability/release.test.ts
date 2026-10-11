import assert from "node:assert/strict";
import { test } from "node:test";
import { resolveSentryRelease } from "./release.ts";

test("prefers an explicit VITE_SENTRY_RELEASE", () => {
  assert.equal(
    resolveSentryRelease({
      VITE_SENTRY_RELEASE: " web-1 ",
      VERCEL_GIT_COMMIT_SHA: "aaaa",
      GITHUB_SHA: "bbbb",
    }),
    "web-1",
  );
});

test("falls back to Vercel then GitHub SHA", () => {
  assert.equal(
    resolveSentryRelease({ VERCEL_GIT_COMMIT_SHA: "deadbeef", GITHUB_SHA: "cccc" }),
    "deadbeef",
  );
  assert.equal(resolveSentryRelease({ GITHUB_SHA: "abcd1234" }), "abcd1234");
  assert.equal(resolveSentryRelease({}), "");
});
