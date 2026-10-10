# INFISICAL.md — ContactLogo

**Infisical is the sole source of truth** for ContactLogo's app-level
settings: secrets, env config, and tunable knobs.  This document is the
contract.  See also the "Infisical sole source of truth" section in
[AGENTS.md](AGENTS.md).

- **Infisical project:** `ContactLogo` (`8a0ae9aa-8b67-443e-943d-c55a767dab50`)
- **Environments:** `prod` only (owner directive 2026-10-10: `dev` and `staging`
  are being retired).  `npm run settings:pull` and the Cursor boot script read
  `prod` and refuse any other `--env` or `INFISICAL_ENV`.
- **Rule:** two visible spaces between sentences in all prose.  No secret
  values in code, logs, PR bodies, or chat — names and metadata only.

## What lives in Infisical (key inventory)

App-level settings — everything the app's behavior depends on that is not
code.  ContactLogo's web app is a static Vite SPA with no backend, so these
are **build-time** settings inlined by Vite (read as `VITE_*` /
`import.meta.env`); the Infisical project is their source of truth and they
reach builds via `npm run settings:pull` (local dev) or the Vercel project
environment (production), both synced from Infisical.

| Key (Infisical) | Used as | Sensitivity | Status |
|---|---|---|---|
| `GOOGLE_CONTACTS_CLIENT_ID` | Google OAuth client id for the Contacts import | Public client id | To be filled by admin |
| `BRANDFETCH_CLIENT_ID` | Brandfetch Logo Link CDN client id (`?c=`) | Public client id | To be filled by admin |
| `LOGODEV_TOKEN` | Logo.dev image CDN token (`?token=`) | **Secret** | To be filled by admin |
| `SENTRY_DSN` | Sentry DSN for the web app | **Secret** | To be filled by admin |
| `SENTRY_ENV` | Sentry environment tag | Config | To be filled by admin |
| `SENTRY_TRACES_SAMPLE_RATE` | Traces sample rate (code default `0.2`) | Knob | In prod |
| `SENTRY_REPLAY_ENABLED` | `false`/`0` disables Session Replay | Knob | To be filled by admin |
| `SENTRY_REPLAY_SESSION_SAMPLE_RATE` | Baseline replay rate (code default `0.1`) | Knob | In prod |
| `SENTRY_REPLAY_ERROR_SAMPLE_RATE` | On-error replay rate (code default `1.0`) | Knob | In prod |
| `DD_APPLICATION_ID` | Datadog browser RUM application id | Public | To be filled by admin |
| `DD_CLIENT_TOKEN` | Datadog browser RUM client token | Public client token | To be filled by admin |
| `DD_SITE` | Datadog site (code default `us5.datadoghq.com`) | Config | In prod |
| `DD_SERVICE` | Datadog service name (code default `contactlogo-web`) | Config | In prod |
| `DD_ENV` | Datadog env tag | Config | To be filled by admin |
| `DD_VERSION` | Datadog version tag | Config | To be filled by admin |
| `DD_REQUIRE` | `1` forces Datadog init even outside production | Knob | To be filled by admin |

"To be filled by admin" means the key is inventoried but has no value yet —
an admin adds it in the Infisical dashboard/CLI and syncs it to Vercel.  No
secret values are ever invented, guessed, or committed.

Out of scope for this project (deliberately not migrated):
- `web/server.mjs` (`PORT`, `DD_API_KEY`, …) is a local/dev leftover — not
  production, documented in AGENTS.md.  If it is ever promoted, its keys
  move into this project first.
- Vercel's own build settings (`vercel.json`) are deployment config, not
  app settings.
- Cache TTLs and timeouts in `web/src/engine/logo-cache.ts`
  (`FETCH_TIMEOUT_MS`, `MISS_TTL_MS`, …) are build-time constants with no
  runtime/admin surface in a static SPA — changing them is a code deploy.
  If a server surface ever exists, promote them to knobs here.

## What does NOT live in Infisical (per-user boundary)

Per-user settings stay in the app's own store and are explicitly out of
scope:

- **Web:** anything the user types into the web Settings page (their own
  Google client id, Brandfetch client id, Logo.dev token) lives in
  `localStorage` (`web/src/engine/settings.ts`) — these are per-user BYO
  keys, not app-level settings.  The web app has no accounts by design.
- **macOS / iOS (Swift):** `SettingsStore` holds the user's Brandfetch API
  key and Logo.dev token in the Keychain plus per-user scan preferences
  (`skipContactsWithExistingPhoto`, `rescueSplitNameBusinesses`,
  `includeSingleNameContacts`, `fetchPersonalAvatars`) in UserDefaults.
  These are single-user local apps — the local user IS the admin, so the
  admin gate is a no-op documented here.  A universal-auth client secret
  must never be embedded in a browser, iOS, Android, or macOS client, so
  native shells do not read Infisical directly.

## The runtime contract (the perf line)

1. **Load at startup / provisioning time.**  The vendored
   `createInfisicalSettings` client (`web/scripts/infisical-settings.ts`)
   loads the full settings set for the project+environment into an
   in-memory Map.  Because the web app is a static SPA, this runs at
   build/dev provisioning time via `npm run settings:pull`
   (`web/scripts/sync-infisical-env.ts`), which writes `.env.local`
   (gitignored).  Startup fails fast naming the missing key and pointing
   here.
2. **Never fetch per-request.**  All runtime reads come from memory (or
   from the Vite-inlined build env).  A per-request Infisical call is the
   one forbidden pattern.
3. **Background refresh.**  The client refreshes on a 5-minute interval
   (tunable via `refreshIntervalMs`); refresh failures log loudly and keep
   serving the last-known-good cache.  Production web builds pick up new
   values on the next Vercel deploy after the env sync.
4. **Write-through on admin save.**  `set()` writes to Infisical FIRST,
   then updates the local cache; a failed Infisical write fails the save
   so the two never diverge silently.

## Admin gating

- There is no settings admin UI — the web app has no accounts by design,
  and the native apps are single-user (the local user is the admin).
- The admin surface for app-level settings is the Infisical
  dashboard/CLI for the `ContactLogo` project, restricted to the fleet's
  automation identity and Jay's Infisical admins.

## How to rotate or change a value

1. Change the value in the Infisical `ContactLogo` project (dashboard or
   CLI), in the `prod` environment.
2. Local dev: re-run `npm run settings:pull` in `web/` (needs
   `INFISICAL_CLIENT_ID` / `INFISICAL_CLIENT_SECRET` in the environment —
   from the operator's secret store, never committed).
3. Production: sync the changed key into the Vercel project's environment
   variables (same value as Infisical prod), then redeploy.  Vercel env is
   a synced copy — Infisical stays the source of truth.
4. Verify: `npm test` in `web/`; the settings tests assert the
   cache/refresh/write-through contract with mocked fetch.

## Why the client is vendored, not depended on

The fleet-shared reference is `createInfisicalSettings` in
`Simple-With-Us/congress-trading-shared`.  Adding that whole package as a
dependency of `contactlogo-web` just for this one module would drag an
unrelated congress-trading dependency tree into a brand-logo web app, so
the module is vendored at `web/scripts/infisical-settings.ts` under the
identical contract.  If the reference contract changes, re-vendor it.
