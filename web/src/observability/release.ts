/**
 * Shared Sentry release name for the web SPA.
 *
 * Prefer an explicit `VITE_SENTRY_RELEASE`, then the Vercel git SHA, then
 * the GitHub Actions SHA.  Empty means the SDK omits `release` (local/CI
 * without a deploy identity).
 */
export type ReleaseEnvSource = {
  VITE_SENTRY_RELEASE?: string;
  VERCEL_GIT_COMMIT_SHA?: string;
  GITHUB_SHA?: string;
};

function trimEnv(value: string | undefined): string {
  return (value ?? "").trim();
}

export function resolveSentryRelease(source: ReleaseEnvSource): string {
  return (
    trimEnv(source.VITE_SENTRY_RELEASE) ||
    trimEnv(source.VERCEL_GIT_COMMIT_SHA) ||
    trimEnv(source.GITHUB_SHA)
  );
}
