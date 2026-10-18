# Auto-Update (Sparkle 2)

Owner ruling, Tue, Sep 29, 2026: every fleet Mac app updates itself seamlessly, through Sparkle 2, from signed releases that CI publishes on each merge to `main`.  CodeCaps piloted the pattern; HogHunter carries a live copy; this document is how ContactLogo implements it.

## What Happens

1. A PR merges to `main` and changes the Mac app (`Apps/ContactLogoMac/`, `Sources/`, `project.yml`, or the build scripts).
2. `.github/workflows/mac-release.yml` builds a universal Release bundle with `xcodegen` + `xcodebuild`, signs it with the Developer ID Application certificate (hardened runtime, secure timestamp, nested code signed inside-out), notarizes and staples the app and the DMG, and writes an appcast whose one item is the new ZIP, signed with ContactLogo's EdDSA key.
3. The workflow publishes a GitHub release tagged `v<VERSION>-build.<N>`, marked latest, carrying `ContactLogo.zip`, `ContactLogo.dmg`, their `.sha256` files, and `appcast.xml`, then confirms the live feed names build N.
4. Every installed copy checks `https://github.com/Simple-With-Us/ContactLogo/releases/latest/download/appcast.xml` once an hour, downloads the new ZIP in the background, verifies its EdDSA signature before unpacking it, and checks that it is signed by the same Developer ID team.
5. As soon as ContactLogo is not the frontmost app, `AppUpdater` installs the update and relaunches.  If the owner is using ContactLogo at that moment, the install waits until they switch away.

Settings shows an "Automatic updates: On/Off" line and a **Check For Updates…** button.  The same command is in the app menu after About.

The iOS companion ships on the same trigger: `.github/workflows/ios-testflight.yml` archives and uploads to TestFlight on every merge to `main` that touches the iOS app (`Apps/ContactLogoiOS/**`, `Sources/`, `project.yml`, `scripts/ios-*`).  The `CL_IOS_TESTFLIGHT_ENABLED` repo variable and the main-ref gate stay in force; enable the variable once the App Store Connect app record exists and `CL_APPLE_ID` is set.

## The Pieces

| Piece | Role |
|---|---|
| `project.yml` | Sparkle 2 (`https://github.com/sparkle-project/Sparkle`, from 2.10.0) as an xcodegen package dependency of the `ContactLogoMac` target only. |
| `Apps/ContactLogoMac/AutoUpdate.swift` | `AutoUpdateAvailability` (should this build run Sparkle at all) and `AppUpdater` (owns `SPUStandardUpdaterController`, installs as soon as the app is idle). |
| `Apps/ContactLogoMac/ContactLogoMacApp.swift` | Starts the updater first thing, adds **Check For Updates…** to the app menu. |
| `Apps/ContactLogoMac/SettingsView.swift` | Settings shows the update status line and the check button. |
| `scripts/mac-release-build.sh` | xcodegen + xcodebuild a universal Release, embed and assert `Sparkle.framework`, write the Sparkle Info.plist keys, sign inside-out, run `codesign --verify --deep --strict`, notarize with an App Store Connect API key when `NOTARY_KEY_*` are set, and run `spctl --assess` on the stapled app and DMG. |
| `scripts/make_appcast.sh` | Runs Sparkle's `generate_appcast` over one archive and checks the result: one item, EdDSA-signed, pointing at the right URL. |
| `.github/workflows/mac-release.yml` | The release job.  Also builds and verifies (never publishes) on PRs that touch the bundle. |
| `.github/actions/infisical-secrets`, `scripts/infisical-fetch.mjs` | Reads the signing certificate and the Sparkle private key from Infisical (universal-auth), with same-named repository secrets as the fallback. |

## Info.plist Keys

`scripts/mac-release-build.sh` writes these into every staged bundle (local `xcodebuild` builds carry none of them, so a dev build never greets the owner with Sparkle's launch alert):

| Key | Value | Why |
|---|---|---|
| `SUFeedURL` | `https://github.com/Simple-With-Us/ContactLogo/releases/latest/download/appcast.xml` | Always the newest release's appcast. |
| `SUPublicEDKey` | `TyN3r1hjY7soNfaw5SCnbpbVLpyY7BKzdE8CyPUpRWg=` | Verifies each archive.  Public, committed in the build script. |
| `SUEnableAutomaticChecks` | true | No "check automatically?" prompt. |
| `SUAutomaticallyUpdate` | true | Download and install without asking. |
| `SUAllowsAutomaticUpdates` | true | Silent installs are permitted. |
| `SUScheduledCheckInterval` | 3600 | Hourly checks. |
| `SUVerifyUpdateBeforeExtraction` | true | EdDSA check before unpacking. |

## Secrets

Names only; no value is ever printed:

- `MAC_CERT_P12_BASE64`, `MAC_CERT_PASSWORD` — the Developer ID Application certificate for team `CC8UTF7ATG`.  Read at runtime from Fleet Secrets (Fleet-OPS Infisical project, `prod`, `/mac-certs`) by the dedicated `mac-release.yml` step, via the org secrets `INFISICAL_FLEET_OPS_PROJECT_ID`, `INFISICAL_UNIVERSAL_AUTH_CLIENT_ID`, `INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET`; same-named GitHub repository secrets are only the `GH_FALLBACK_` path.
- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` — the App Store Connect API key; `notarytool` signs in with it, and `ios-testflight.yml` uses it for the TestFlight upload.  Canonical home is Fleet Secrets (Fleet-OPS, `prod`, `/asc`); same-named repository secrets as the copies.
- `IOS_DIST_P12_BASE64`, `IOS_DIST_P12_PASSWORD` — the Apple Distribution certificate for the iOS archive.  Canonical home is Fleet Secrets (Fleet-OPS, `prod`, `/mac-certs`); same-named repository secrets as the copies.
- `SPARKLE_ED_PRIVATE_KEY` — the EdDSA private key (base64 of the 32-byte seed) that signs each update archive; repository secret, synced from the fleet key store.  Generated 2026-10-15 for ContactLogo; the matching public key is committed above.

With any of them missing the Mac job still builds the bundle and verifies its signature, then skips publishing with a notice that names what is missing.

## Rollback

Every release is a GitHub release with its own appcast; rolling back is publishing the previous build's archive as the new latest (or re-running the workflow from the older commit).  The appcast never carries more than one item, so there is no feed history to rewrite.

## iOS TestFlight

`ios-testflight.yml` mirrors the HogHunter lane: `xcodegen` + `xcodebuild archive` of the `ContactLogoiOS` scheme (bundle `com.contactlogo`, team `CC8UTF7ATG`, automatic signing with `-allowProvisioningUpdates`), identity validation via `scripts/validate-ios-release.py`, export, and `altool` upload to the App Store Connect app named by the `CL_APPLE_ID` repo variable.  Push ships always upload; manual dispatch keeps its `upload` input.  The workflow is inert until the `CL_IOS_TESTFLIGHT_ENABLED` repo variable is set to `true`.

## Mac TestFlight

Owner ask, Sat, Oct 17, 2026 (CL-203): a merge to `main` that changes the Mac app also uploads a fresh TestFlight build of ContactLogo for Mac, with no human step.  Sparkle and TestFlight are two channels for two audiences and both run on the same merge: Sparkle updates the copies installed from the signed GitHub release, TestFlight feeds the Mac App Store Connect record (ASC app 6804248235, bundle `com.contactlogo.macos`, internal testing).

### What Happens

1. A PR merges to `main` and touches `Apps/ContactLogoMac/`, `Apps/ContactLogoMacAppStore/`, `Sources/`, `project.yml`, or the ship tooling.
2. `.github/workflows/mac-testflight.yml` starts.  A cheap Linux job runs `scripts/ios-scheduled-ship-gate.sh`; a push or a manual dispatch always passes it.
3. The macOS job loads the App Store Connect key, the Apple Distribution certificate and the Mac installer certificate from Fleet Secrets (Fleet-OPS, `prod`, `/asc` and `/mac-certs`), imports the certificates into a throwaway keychain, and runs `scripts/ios-fleet/ship-testflight.sh contactlogo-mac`.
4. The ship script regenerates the project with XcodeGen, installs the `ContactLogo for Mac AppStore` profile (`scripts/mac-install-appstore-profiles.sh`), archives the `ContactLogoMacAppStore` scheme, wraps the archive into a signed installer package (`scripts/mac-export-appstore-pkg.sh`), uploads it with `altool`, declares export compliance, and publishes the What to Test note.
5. Marketing version is `1.0.N` with N one higher than anything App Store Connect holds for the Mac platform; the build number is the UTC time, `YYYYMMDDHHMM`.

The ship script keeps its own limits: one TestFlight build per app per hour, and a skip when `HEAD` was already shipped.  No workflow sets `IOS_TF_MIN_INTERVAL_SEC`; the `force_ship` dispatch input is a per-run choice that defaults to off.  An hourly `schedule:` tick catches a merge that landed inside the hour of the previous ship, and a bot merge, which GitHub does not turn into a push event.  The tick ships only when a Mac source path changed since the last successful ship, so a web, Android or iOS-only commit never produces a Mac build.

A run on any ref other than `main`, or a dispatch with `validate_only`, builds the signed package and has App Store Connect validate it (`altool --validate-app`) without uploading.

### Why The App Store Build Is A Separate Target

`ContactLogoMacAppStore` compiles the same sources and uses the same bundle id, Info.plist and assets as `ContactLogoMac`, with two differences:

- It does not link Sparkle.  The Mac App Store forbids a self-updating app, and Sparkle's `Autoupdate` and `Updater.app` executables are not sandboxed, which App Store Connect rejects.  `Apps/ContactLogoMacAppStore/AutoUpdateStub.swift` replaces `AutoUpdate.swift` and defines the same two names (`AppUpdater`, `AutoUpdateAvailability`), so no call site changes.  Settings shows "Automatic updates: Off" and "Check For Updates…" stays greyed out.
- Its entitlements (`ContactLogoMacAppStore.entitlements`) drop the Sparkle InstallerLauncher mach-lookup exceptions.  Keep the two entitlement files in step for everything else.

Developer ID releases still ship the `ContactLogoMac` target from `mac-release.yml`.

### Signing

Xcode's provisioning service (`developerservices2.apple.com`) answers the fleet App Store Connect key with HTTP 401, so automatic signing cannot work on a hosted runner (found on Socratic-Trade 2026-09-30).  Release for the App Store target therefore signs manually: `CODE_SIGN_IDENTITY = Apple Distribution` and `PROVISIONING_PROFILE_SPECIFIER = ContactLogo for Mac AppStore`, a `MAC_APP_STORE` profile that holds the `group.com.contactlogo` App Group and the Apple Distribution and Mac Installer Distribution certificates.  `scripts/ios-fleet/mac-appstore-profiles.json` maps the bundle id to that profile name and `scripts/mac-install-appstore-profiles.sh` downloads it over the App Store Connect REST API.

The package is built with `productbuild`, not `xcodebuild -exportArchive`, which hangs on `productsign` on hosted runners (CodeCaps #95).

Renewal: the profile and both certificates expire on 2027-06-30.  When the fleet renews the certificates, create a new `MAC_APP_STORE` profile named `ContactLogo for Mac AppStore` for `com.contactlogo.macos` with the renewed Apple Distribution and Mac Installer Distribution certificates (the developer portal, or `POST /v1/profiles` through `scripts/ios-fleet/asc-api.mjs`).  A missing or expired profile fails the ship in `mac-install-appstore-profiles.sh` with a message that says so.

### The Vendored Ship Tooling

`scripts/ios-fleet/` holds the fleet ship script and its client, vendored because a hosted runner has no `/Users/jay/apps/ios-fleet`: `ship-testflight.sh` (the Socratic-Trade copy, plus the macOS manual-signing path described in its header), `asc-api.mjs` (the central client, with one change:  the What to Test release stamp reads `Sun, Oct 18, 2026 at 9:05am`, the owner clock with no timezone abbreviation, as AGENT-SYNC writes it, where the central client still prints `AM CT`), the two `ExportOptions` plists, `apps.json` (the ship registry) and `mac-appstore-profiles.json`.  `scripts/ios-fleet.sha256` pins all of them; `bash scripts/ios-fleet-pin.sh --update` refreshes the pin, and the change lands in a reviewed PR.  CI (`ship-tooling`) and the ship job both check the pin.

`scripts/check-mac-testflight-contract.py` runs in CI and fails when the workflow, `project.yml`, the registry and the profile map stop agreeing (a trigger path dropped, Sparkle linked into the store target, a profile name that no longer matches).

### Checking A Ship

- `gh workflow view mac-testflight.yml` must say `active`.  If the workflow is ever disabled, merges stop reaching TestFlight silently.
- The run's summary lists the marketing version, the build number, and the ship-gate decision.  `ship-gate: skip` is normal inside the hour of a previous ship; the hourly tick ships it later.
- `node scripts/ios-fleet/asc-api.mjs GET "/v1/builds?filter[app]=6804248235&sort=-uploadedDate&limit=3"` (with the App Store Connect credentials in the environment) lists the newest builds; the newest should be `VALID` and recent.

### Owner Actions

- The Mac record needs an internal TestFlight group with the owner in it for the build to appear in the TestFlight app on the Mac.  App Store Connect shows the build either way.
