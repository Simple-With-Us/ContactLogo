# ContactLogo reads Infisical prod only (2026-10-10)

Owner directive (2026-10-10): the `dev` and `staging` environments of the ContactLogo Infisical project (`8a0ae9aa-8b67-443e-943d-c55a767dab50`) are being retired.  Every provisioning path now selects `prod`.

## What changed

- `web/scripts/infisical-environment.ts` (new) resolves the environment.  It returns `prod` by default and throws on any other slug from `--env` or `INFISICAL_ENV`.
- `npm run settings:pull` (`web/scripts/sync-infisical-env.ts`) uses it, so it defaults to `prod` instead of `dev` and exits non-zero on a non-prod request.
- The Infisical coordinates file under `.cursor/` selects `prod`, and `scripts/cursor-cloud-start.sh` defaults to `prod` and exits 1 on any other `INFISICAL_ENV` (an uncredentialed boot still exits 0, as before).
- `INFISICAL.md` and `AGENTS.md` describe the prod-only contract.  The five keys marked "In dev" are now "In prod".
- `web/package.json` runs the new test file with `npm test`.

## Production impact

None.  The Vercel project has no Infisical variables, and the static build never reads Infisical at deploy time.

## Keys

The prod environment now holds nine keys: the four that were already there (`SENTRY_DSN`, `SENTRY_DSN_MACOS`, `SENTRY_DSN_WEB`, `VITE_SENTRY_DSN`) plus the five moved from dev (`DD_SERVICE`, `DD_SITE`, `SENTRY_REPLAY_ERROR_SAMPLE_RATE`, `SENTRY_REPLAY_SESSION_SAMPLE_RATE`, `SENTRY_TRACES_SAMPLE_RATE`).  No dev-only key was left uncopied.
