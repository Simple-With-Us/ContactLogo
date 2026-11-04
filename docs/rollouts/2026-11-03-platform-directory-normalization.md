# Platform directory normalization

The current source layout puts each platform implementation under the lowercase `apps/` container to avoid case-fold collisions on macOS.  The move preserves source interiors, schemes, product identifiers, bundle identifiers, application identifiers, job names and public routes.

| Previous path | Current path | Notes |
| --- | --- | --- |
| `Apps/ContactLogoAndroid/` | `apps/android/` | Android app and tests |
| `Apps/ContactLogoiOS/` | `apps/ios/` | iOS app and tests |
| `Apps/ContactLogoMac/` | `apps/macos/` | macOS direct-distribution app |
| `Apps/ContactLogoMacAppStore/` | `apps/macos-app-store/` | Existing macOS App Store distribution variant |
| `web/` | `apps/web/` | Web app and tests |

Historical rollout, audit and handoff documents retain their original path citations as dated evidence.  Current documentation and build references use the new paths.

## Staged web-root rollout

Phase 1 keeps a temporary top-level `web/` deployment bridge because Vercel still uses the existing project root.  `apps/web/` remains the canonical source directory.  The tracked bridge must contain the exact same relative file set, Git blob bytes and executable modes as `apps/web/`; symlinks, extra files and partial copies fail the layout gate.  Only tracked regular files are mirrored, and the bridge is read-only compatibility content rather than a second source tree.

The rollout order is: merge this bridge and validation change; switch the Vercel project root to `apps/web/`; verify the new-root production deployment; then remove top-level `web/` and restore the layout gate that forbids it.  The final cleanup is a separate phase and must not happen before the new Vercel root and production deployment are verified.

`scripts/deploy/vercel-config.json` keeps `rootDirectory` on `web` for the whole bridge phase, and `watch` on `web/**` with it.  The production catch-up asserts the live Vercel project root against that value before it looks at anything else, so declaring `apps/web` while the project still points at `web` makes the deploy job refuse with a root directory drift and blocks every deployment until the switch actually happens.  Flip both values together, in the cutover phase, after the Vercel project root has been switched and the new-root deployment has been verified.

The repository build and hosted CI checks validate canonical directories, case-fold uniqueness and byte/mode equality of the temporary bridge.  This phase does not claim that Vercel configuration was updated or deployed.
