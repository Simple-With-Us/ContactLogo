/**
 * Shared Sentry release name for the web SPA.
 *
 * Uses the fleet deploy identity already present on Vercel and GitHub
 * Actions (`VERCEL_GIT_COMMIT_SHA`, then `GITHUB_SHA`).  `VITE_SENTRY_RELEASE`
 * is no longer an admin/env input — Vite inlines the resolved SHA under that
 * name for the browser SDK.  Empty means the SDK omits `release` (local
 * builds without a deploy identity).
 */
export type ReleaseEnvSource = {
  VERCEL_GIT_COMMIT_SHA?: string;
  GITHUB_SHA?: string;
};

function trimEnv(value: string | undefined): string {
  return (value ?? "").trim();
}

export function resolveSentryRelease(source: ReleaseEnvSource): string {
  return trimEnv(source.VERCEL_GIT_COMMIT_SHA) || trimEnv(source.GITHUB_SHA);
}
