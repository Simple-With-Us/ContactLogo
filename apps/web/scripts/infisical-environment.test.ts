/**
 * ContactLogo reads Infisical prod only (owner directive 2026-10-10).  The
 * resolver defaults to prod and refuses every other slug, from the flag or
 * from INFISICAL_ENV.
 */
import test from "node:test";
import assert from "node:assert/strict";
import {
  INFISICAL_ENVIRONMENT,
  resolveInfisicalEnvironment,
} from "./infisical-environment.ts";

test("defaults to prod when nothing is requested", () => {
  assert.equal(INFISICAL_ENVIRONMENT, "prod");
  assert.equal(resolveInfisicalEnvironment([], {}), "prod");
  assert.equal(resolveInfisicalEnvironment([], { INFISICAL_ENV: "" }), "prod");
  assert.equal(resolveInfisicalEnvironment(["--env"], {}), "prod");
});

test("accepts an explicit prod request from the flag or the variable", () => {
  assert.equal(resolveInfisicalEnvironment(["--env", "prod"], {}), "prod");
  assert.equal(resolveInfisicalEnvironment([], { INFISICAL_ENV: "prod" }), "prod");
  assert.equal(resolveInfisicalEnvironment(["--env", "prod"], { INFISICAL_ENV: "prod" }), "prod");
});

test("refuses dev and staging from the flag", () => {
  assert.throws(() => resolveInfisicalEnvironment(["--env", "dev"], {}), /Refusing Infisical environment "dev"/);
  assert.throws(() => resolveInfisicalEnvironment(["--env", "staging"], {}), /Refusing Infisical environment "staging"/);
});

test("refuses dev and staging from INFISICAL_ENV", () => {
  assert.throws(() => resolveInfisicalEnvironment([], { INFISICAL_ENV: "dev" }), /prod" only/);
  assert.throws(() => resolveInfisicalEnvironment([], { INFISICAL_ENV: "staging" }), /prod" only/);
});

test("the flag takes precedence over the variable, as before", () => {
  assert.equal(resolveInfisicalEnvironment(["--env", "prod"], { INFISICAL_ENV: "dev" }), "prod");
  assert.throws(() => resolveInfisicalEnvironment(["--env", "dev"], { INFISICAL_ENV: "prod" }), /dev/);
});
