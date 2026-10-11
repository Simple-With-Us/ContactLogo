import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { countLogoMatch, sentryStarted, startSentry } from "./sentry.ts";

test("startSentry is inert without a DSN", () => {
  startSentry();
  assert.equal(sentryStarted(), false);
});

test("countLogoMatch never throws when Sentry is dark", () => {
  assert.doesNotThrow(() => countLogoMatch(0));
  assert.doesNotThrow(() => countLogoMatch(12));
});

test("Android native Sentry inits masked Replay and profiling", () => {
  const app = readFileSync(
    join(
      dirname(fileURLToPath(import.meta.url)),
      "../../../Apps/ContactLogoAndroid/app/src/main/java/com/contactlogo/ContactLogoApp.kt",
    ),
    "utf8",
  );
  assert.match(app, /SentryAndroid\.init/);
  assert.match(app, /sessionReplay\.sessionSampleRate = 0\.1/);
  assert.match(app, /sessionReplay\.onErrorSampleRate = 1\.0/);
  assert.match(app, /profilesSampleRate = 0\.1/);
  assert.match(app, /setMaskAllText\(true\)/);
  assert.match(app, /options\.release = "\$\{BuildConfig\.VERSION_NAME\}\+\$\{BuildConfig\.VERSION_CODE\}"/);
  const gradle = readFileSync(
    join(
      dirname(fileURLToPath(import.meta.url)),
      "../../../Apps/ContactLogoAndroid/app/build.gradle.kts",
    ),
    "utf8",
  );
  assert.match(gradle, /id\("io\.sentry\.android\.gradle"\)/);
  assert.match(gradle, /autoUploadProguardMapping/);
  assert.match(gradle, /System\.getenv\("SENTRY_DSN"\)/);
});

test("sentry configures subtle feedback integration", () => {
  const sentrySrc = readFileSync(
    join(dirname(fileURLToPath(import.meta.url)), "sentry.ts"),
    "utf8",
  );
  assert.match(sentrySrc, /feedbackIntegration\(/);
  assert.match(sentrySrc, /autoInject:\s*false/);
  assert.match(sentrySrc, /formTitle:\s*"Report a Problem"/);
  assert.match(sentrySrc, /export function openSentryFeedback/);
});

test("native Cocoa and the ship helper inject DSN and upload dSYMs", () => {
  const ios = readFileSync(
    join(
      dirname(fileURLToPath(import.meta.url)),
      "../../../Apps/ContactLogoiOS/SentryTelemetry.swift",
    ),
    "utf8",
  );
  const mac = readFileSync(
    join(
      dirname(fileURLToPath(import.meta.url)),
      "../../../Apps/ContactLogoMac/SentryTelemetry.swift",
    ),
    "utf8",
  );
  const ci = readFileSync(
    join(dirname(fileURLToPath(import.meta.url)), "../../../.github/workflows/ci.yml"),
    "utf8",
  );
  const dsym = readFileSync(
    join(
      dirname(fileURLToPath(import.meta.url)),
      "../../../scripts/ios-fleet/upload-sentry-dsyms.sh",
    ),
    "utf8",
  );
  assert.match(ios, /options\.releaseName/);
  assert.match(mac, /options\.releaseName/);
  assert.match(ios, /SENTRY_DSN/);
  assert.match(ci, /sentry_secret:\s*SENTRY_DSN_MACOS/);
  assert.match(ci, /sentry_secret:\s*SENTRY_DSN/);
  assert.match(ci, /secrets\[matrix\.sentry_secret\]/);
  assert.match(ci, /upload-sentry-dsyms\.sh/);
  assert.match(dsym, /contactlogo-macos/);
  assert.match(dsym, /debug-files upload/);
  assert.match(dsym, /SENTRY_AUTH_TOKEN unset/);
});

test("web Sentry sets a release and emits logs when a DSN is present", () => {
  const sentrySrc = readFileSync(
    join(dirname(fileURLToPath(import.meta.url)), "sentry.ts"),
    "utf8",
  );
  const viteSrc = readFileSync(
    join(dirname(fileURLToPath(import.meta.url)), "../../vite.config.ts"),
    "utf8",
  );
  assert.match(sentrySrc, /resolveSentryRelease/);
  assert.match(sentrySrc, /release:\s*release \|\| undefined/);
  assert.match(sentrySrc, /consoleLoggingIntegration/);
  assert.match(sentrySrc, /logger\.info\("contactlogo\.web\.boot"/);
  assert.match(viteSrc, /sentryVitePlugin/);
  assert.match(viteSrc, /SENTRY_AUTH_TOKEN/);
  assert.match(viteSrc, /filesToDeleteAfterUpload/);
  assert.match(viteSrc, /project:\s*"contactlogo"/);
  const syncSrc = readFileSync(
    join(dirname(fileURLToPath(import.meta.url)), "../../scripts/sync-infisical-env.ts"),
    "utf8",
  );
  assert.match(syncSrc, /noVitePrefix[\s\S]*SENTRY_AUTH_TOKEN/);
});
