/**
 * Which Infisical environment ContactLogo reads.
 *
 * Owner directive (2026-10-10): prod is the only environment.  The `dev` and
 * `staging` environments of the ContactLogo Infisical project are being
 * retired, so every provisioning path selects `prod` and refuses anything else
 * rather than quietly reading a retired environment.
 */
export const INFISICAL_ENVIRONMENT = "prod";

/**
 * Resolve the environment for a provisioning run from a `--env <slug>` flag
 * (checked first) and the `INFISICAL_ENV` variable.  Returns `"prod"`.  A
 * request for any other slug throws, so `settings:pull` exits non-zero.
 */
export function resolveInfisicalEnvironment(
  argv: string[],
  env: Record<string, string | undefined> = process.env,
): string {
  const idx = argv.indexOf("--env");
  const flag = idx !== -1 ? argv[idx + 1] : undefined;
  const requested = (flag || env.INFISICAL_ENV || "").trim();
  if (requested && requested !== INFISICAL_ENVIRONMENT) {
    throw new Error(
      `Refusing Infisical environment "${requested}": ContactLogo reads "${INFISICAL_ENVIRONMENT}" only ` +
        `(dev and staging are retired).  Drop the --env flag or set INFISICAL_ENV=${INFISICAL_ENVIRONMENT}.`,
    );
  }
  return INFISICAL_ENVIRONMENT;
}
