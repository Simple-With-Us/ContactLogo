#!/usr/bin/env bash
# Build a Mac App Store installer package (.pkg) from an .xcarchive without
# `xcodebuild -exportArchive`.  Hosted runners have hung on exportArchive's
# productsign step (CodeCaps #95), so the package is made with productbuild,
# signed with the Mac installer certificate that mac-appstore-gm-prepare.sh
# imported.  The app inside the archive is already signed (Apple Distribution
# and the Mac App Store profile, by the Release configuration of the
# ContactLogoMacAppStore target).
#
# Usage: mac-export-appstore-pkg.sh <archive.xcarchive> <out-dir> <bundle-id>
# Prints the package path as its last line of stdout.  Never prints credentials.
# ASCII-only (Apple bash 3.2 safe).
set +o xtrace
set -euo pipefail
umask 077

die() { echo "error: $*" >&2; exit 1; }
log() { echo "[mac-pkg] $*" >&2; }

ARCHIVE="${1:-}"
OUT_DIR="${2:-}"
BUNDLE_ID="${3:-}"
[[ -d "$ARCHIVE" ]] || die "archive missing: ${ARCHIVE:-unset}"
[[ -n "$OUT_DIR" ]] || die "out dir required"
[[ -n "$BUNDLE_ID" ]] || die "bundle id required"
mkdir -p "$OUT_DIR"

APP="$(find "$ARCHIVE/Products" -maxdepth 3 -name '*.app' -type d | head -1 || true)"
[[ -n "$APP" && -d "$APP" ]] || die "no .app under $ARCHIVE/Products"
APP_NAME="$(basename "$APP" .app)"
log "app=$(basename "$APP")"

# The archived app must be a store build: no Sparkle, an embedded profile, and
# the sandbox on.  A mistake here would only surface as an App Store Connect
# rejection after the upload, so fail before the package exists.
[[ ! -e "$APP/Contents/Frameworks/Sparkle.framework" ]] || die "Sparkle.framework is inside the App Store build"
[[ -f "$APP/Contents/embedded.provisionprofile" ]] || die "no embedded.provisionprofile; the archive was not signed with the Mac App Store profile"
codesign --verify --deep --strict "$APP" || die "codesign verification failed for the archived app"
ENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
printf '%s' "$ENTS" | grep -q 'com.apple.security.app-sandbox' || die "the archived app is not sandboxed"
log "store-build checks passed (no Sparkle, profile embedded, sandboxed, signature verifies)"

# Installer identity: "3rd Party Mac Developer Installer" (the name Apple gave
# the certificate until 2024) or "Mac Installer Distribution".  Installer
# certificates do not show up under the codesigning policy, so list them all.
KC_PATH=""
if [[ -n "${RUNNER_TEMP:-}" && -f "${RUNNER_TEMP}/app-signing.keychain-db" ]]; then
  KC_PATH="${RUNNER_TEMP}/app-signing.keychain-db"
  if [[ -f "${RUNNER_TEMP}/app-signing-kc-pass" ]]; then
    KC_PASS="$(cat "${RUNNER_TEMP}/app-signing-kc-pass")"
    security unlock-keychain -p "$KC_PASS" "$KC_PATH" >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC_PATH" >/dev/null || true
  fi
fi
INSTALLER_ID="${MAC_INSTALLER_IDENTITY:-}"
if [[ -z "$INSTALLER_ID" ]]; then
  IDS="$(security find-identity -v ${KC_PATH:+"$KC_PATH"} 2>/dev/null || true)"
  INSTALLER_ID="$(printf '%s\n' "$IDS" | sed -nE 's/^ *[0-9]+\) [0-9A-F]{40} "((3rd Party Mac Developer Installer|Mac Installer Distribution):[^"]*)"$/\1/p' | head -1)"
fi
[[ -n "$INSTALLER_ID" ]] || die "no Mac installer identity in the keychain (need 3rd Party Mac Developer Installer or Mac Installer Distribution)"
log "installer identity ready (name length ${#INSTALLER_ID})"

# The store requires LSMinimumSystemVersion to equal the product definition's
# minimum OS version (ASC 90264); productbuild --product copies it from the
# app's Info.plist.
INFO="$APP/Contents/Info.plist"
MIN_VER="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO" 2>/dev/null || true)"
[[ -n "$MIN_VER" ]] || die "Info.plist has no LSMinimumSystemVersion"
MARKETING="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO" 2>/dev/null || true)"
[[ -n "$MARKETING" ]] || die "Info.plist has no CFBundleShortVersionString"
log "LSMinimumSystemVersion=${MIN_VER} marketing=${MARKETING}"

PKG_PATH="${OUT_DIR}/${APP_NAME}.pkg"
rm -f "$PKG_PATH"
productbuild \
  --component "$APP" /Applications \
  --product "$INFO" \
  --sign "$INSTALLER_ID" \
  ${KC_PATH:+--keychain "$KC_PATH"} \
  --identifier "$BUNDLE_ID" \
  --version "$MARKETING" \
  "$PKG_PATH" >&2

[[ -f "$PKG_PATH" ]] || die "package was not produced"
pkgutil --check-signature "$PKG_PATH" >/dev/null 2>&1 || die "package signature check failed"
log "pkg=$(basename "$PKG_PATH") size=$(wc -c < "$PKG_PATH") bytes, signature ok"
printf '%s\n' "$PKG_PATH"
