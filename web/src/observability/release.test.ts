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

test("empty or whitespace VITE_SENTRY_RELEASE falls through to Vercel SHA", () => {
  assert.equal(
    resolveSentryRelease({
      VITE_SENTRY_RELEASE: "",
      VERCEL_GIT_COMMIT_SHA: "sha",
      GITHUB_SHA: "bbbb",
    }),
    "sha",
  );
  assert.equal(
    resolveSentryRelease({
      VITE_SENTRY_RELEASE: "   ",
      VERCEL_GIT_COMMIT_SHA: "sha",
      GITHUB_SHA: "bbbb",
    }),
    "sha",
  );
});
