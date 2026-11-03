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

The repository build and hosted CI checks validate this layout.  The external Vercel project root still needs its separately managed cutover to `apps/web/`; this change does not claim that deployment configuration was updated or deployed.
