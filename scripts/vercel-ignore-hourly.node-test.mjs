import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const ignoreScript = join(repositoryRoot, "apps/web/vercel-ignore-hourly.sh");

test("Vercel auth header is read from curl config stdin, not argv or output", (t) => {
  const temp = mkdtempSync(join(tmpdir(), "contactlogo-vercel-ignore-"));
  t.after(() => rmSync(temp, { recursive: true, force: true }));

  const bin = join(temp, "bin");
  mkdirSync(bin);
  const argsPath = join(temp, "curl-args");
  const configPath = join(temp, "curl-config");
  const curlPath = join(bin, "curl");
  writeFileSync(
    curlPath,
    "#!/bin/sh\nprintf '%s\\0' \"$@\" > \"$CURL_ARGS_FILE\"\ncat > \"$CURL_CONFIG_FILE\"\nprintf '{\\\"deployments\\\":[]}'\n",
  );
  chmodSync(curlPath, 0o755);

  const fixtureToken = "fixture-token-never-use";
  const result = spawnSync("bash", [ignoreScript], {
    cwd: repositoryRoot,
    encoding: "utf8",
    env: {
      ...process.env,
      PATH: `${bin}:${process.env.PATH ?? ""}`,
      CURL_ARGS_FILE: argsPath,
      CURL_CONFIG_FILE: configPath,
      VERCEL_ENV: "production",
      VERCEL_FORCE_DEPLOY: "",
      VERCEL_IGNORE_WATCH: "",
      VERCEL_ORG_ID: "",
      VERCEL_PROJECT_ID: "fixture-project",
      VERCEL_TOKEN: fixtureToken,
      VERCEL_GIT_PREVIOUS_SHA: "9f3ccd1392779a2c97c696cec8793ec6fb0d6c91",
      VERCEL_GIT_COMMIT_SHA: "837f9bcf1ccda2fafa30782b8a338498c3ec60c7",
    },
  });

  assert.equal(result.status, 1, result.stderr);
  assert.match(result.stdout, /build production/);
  assert.doesNotMatch(`${result.stdout}${result.stderr}`, new RegExp(fixtureToken));

  const curlArgs = readFileSync(argsPath, "utf8");
  const curlConfig = readFileSync(configPath, "utf8");
  assert.match(curlArgs, /--config/);
  assert.doesNotMatch(curlArgs, new RegExp(fixtureToken));
  assert.match(curlConfig, new RegExp(`header = .*Authorization: Bearer ${fixtureToken}`));
});
