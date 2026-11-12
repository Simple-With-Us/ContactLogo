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

The repository build and hosted CI checks validate canonical directories, case-fold uniqueness and byte/mode equality of the temporary bridge.  This phase does not claim that Vercel configuration was updated or deployed.

## Bridge build output has to stay ignored

The bridge left the build-output ignore rule on the pre-bridge path, so the ignore rule still named `apps/web/dist/` while the deploy job builds `web/`.  `vercel build` writes `web/dist/`, the deploy checkout was therefore dirty at publish time, and the Vercel CLI stamps a dirty marker on any deployment made from a dirty tree.  The production catch-up refuses a deployment carrying that marker because its SHA is not a verified baseline, so the deploy job uploaded the build, aliased production, and then failed its receipt check.  The layout gate now requires the build output of both web roots to be ignored, which keeps the deploy checkout clean so a published deployment can be verified against a commit.

## An unverifiable production baseline is republished, not trusted

The catch-up refuses to trust a production deployment that carries a dirty marker, because the marker means the published content cannot be tied to a commit.  A refusal is safe, but it cannot repair itself: the next run reads the same unverifiable baseline and refuses again, so production stays unverifiable until something else publishes.  The catch-up now treats an unverifiable baseline as a reason to republish main, which replaces it with a deployment made from a clean checkout and restores the invariant.  The republish obeys the same three-hour cooldown, the same exact-main CI requirement and the same ancestor rule as any other publish, so it only ever moves production forward, and the receipt check still refuses a dirty deployment, so an unverifiable publish never becomes the baseline.

## A dirty checkout is refused before the upload

The Vercel CLI marks a deployment dirty when the tree it uploaded from was not clean, and the receipt check refuses a dirty deployment.  Publishing from a dirty tree therefore uploads a build and then fails the receipt, which reads as a deploy failure even though the upload succeeded.  The catch-up now checks the checkout before it decides to publish, so a dirty tree is reported as the cause it is, before any upload, and the build output of the Vercel root has to be ignored for that check to pass.
