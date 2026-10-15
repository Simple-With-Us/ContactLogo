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
