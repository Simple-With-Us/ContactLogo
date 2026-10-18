#!/usr/bin/env bash
# Prepare the stable GitHub-hosted macOS runner to archive ContactLogo for Mac
# for the Mac App Store and TestFlight.  Writes the App Store Connect
# credentials file the fleet ship script reads, and imports these identities
# into a throwaway keychain:
#   - Apple Distribution                  (IOS_DIST_P12_*)  signs the app
#   - 3rd Party Mac Developer Installer   (MAC_APPSTORE_INSTALLER_P12_*)  signs the package
# The App Store Connect key must already be staged by scripts/ios-stage-asc-key.sh
# (ASC_KEY_PATH).  Never prints secret values.  Fails closed on a beta macOS host.
set +o xtrace
set -euo pipefail
umask 077

die() { echo "error: $*" >&2; exit 1; }
log() { echo "[mac-gm] $*"; }

os=$(sw_vers -productVersion)
build=$(sw_vers -buildVersion)
log "macOS ${os} (${build})"
# Apple seed trains stamp a lowercase letter after the build number
# (26A5406e).  GM builds end in digits (25F84, 24G720).
if echo "$build" | grep -Eq '[0-9][a-z]$'; then
  die "beta macOS host ${os} (${build}).  App Store review rejects these as INVALID_BINARY.  Use GitHub-hosted macos-latest (GM)."
fi

: "${ASC_KEY_ID:?ASC_KEY_ID required}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID required}"
: "${ASC_KEY_PATH:?ASC_KEY_PATH required; stage the key file first}"
: "${IOS_DIST_P12_BASE64:?IOS_DIST_P12_BASE64 required}"
: "${IOS_DIST_P12_PASSWORD:?IOS_DIST_P12_PASSWORD required}"

# Fleet-OPS /mac-certs holds two installer certificates:  MAC_APPSTORE_INSTALLER_*
# is the "3rd Party Mac Developer Installer" the store needs;  MAC_INSTALLER_* is
# the "Developer ID Installer" for notarized packages, and is NOT used here
# (the first CL-203 run found that out: it holds no App Store installer).
: "${MAC_APPSTORE_INSTALLER_P12_BASE64:?MAC_APPSTORE_INSTALLER_P12_BASE64 required}"
: "${MAC_APPSTORE_INSTALLER_P12_PASSWORD:?MAC_APPSTORE_INSTALLER_P12_PASSWORD required}"
INSTALLER_NAMES="MAC_APPSTORE_INSTALLER"

SECRETS_DIR="${HOME}/.secrets"
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

[[ -s "$ASC_KEY_PATH" ]] || die "ASC_KEY_PATH has no key file"
chmod 600 "$ASC_KEY_PATH"

ENV_PATH="${SECRETS_DIR}/appstore-connect.env"
{
  printf 'ASC_KEY_ID=%s\n' "$ASC_KEY_ID"
  printf 'ASC_ISSUER_ID=%s\n' "$ASC_ISSUER_ID"
  printf 'ASC_KEY_PATH=%s\n' "$ASC_KEY_PATH"
} > "$ENV_PATH"
chmod 600 "$ENV_PATH"

DIST_P12="${SECRETS_DIR}/ios-distribution.p12"
INST_DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/mac-installer.XXXXXX")"
trap 'rm -f "$DIST_P12"; rm -rf "$INST_DIR"' EXIT
printf '%s' "$IOS_DIST_P12_BASE64" | base64 --decode > "$DIST_P12"
chmod 600 "$DIST_P12"
for n in $INSTALLER_NAMES; do
  b64="${n}_P12_BASE64"
  printf '%s' "${!b64}" | base64 --decode > "${INST_DIR}/${n}.p12"
  chmod 600 "${INST_DIR}/${n}.p12"
done

KC_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
KC_PATH="${KC_DIR}/app-signing.keychain-db"
KC_PASS_FILE="${KC_DIR}/app-signing-kc-pass"
openssl rand -base64 24 > "$KC_PASS_FILE"
chmod 600 "$KC_PASS_FILE"
KC_PASS=$(cat "$KC_PASS_FILE")

security delete-keychain "$KC_PATH" >/dev/null 2>&1 || true
security create-keychain -p "$KC_PASS" "$KC_PATH"
security set-keychain-settings -lut 21600 "$KC_PATH"
security unlock-keychain -p "$KC_PASS" "$KC_PATH"
# -A lets any tool use the key: productbuild's installer signing prompts (and
# hangs) on a hosted runner with a narrower -T list.  The keychain is created
# for this job and deleted at its end.
security import "$DIST_P12" -k "$KC_PATH" -P "$IOS_DIST_P12_PASSWORD" -A >/dev/null
for n in $INSTALLER_NAMES; do
  pw="${n}_P12_PASSWORD"
  security import "${INST_DIR}/${n}.p12" -k "$KC_PATH" -P "${!pw}" -A >/dev/null || die "could not import ${n}_P12_BASE64"
done
rm -f "$DIST_P12"
rm -rf "$INST_DIR"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC_PATH" >/dev/null
security unlock-keychain -p "$KC_PASS" "$KC_PATH"
security list-keychain -d user -s "$KC_PATH" login.keychain-db

# Identity names only; never dump key material.  The kinds of identity the
# keychain holds (the text before the colon in the certificate name) go to the
# log, so a wrong secret is visible there.
KINDS="$(security find-identity -v "$KC_PATH" | sed -nE 's/^ *[0-9]+\) [0-9A-F]{40} "([^:"]*):.*$/\1/p' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
log "identities in the keychain: ${KINDS:-none}"
if ! security find-identity -v -p codesigning "$KC_PATH" | grep -q 'Apple Distribution'; then
  die "imported keychain has no Apple Distribution identity"
fi
if ! security find-identity -v "$KC_PATH" | grep -Eq '3rd Party Mac Developer Installer|Mac Installer Distribution'; then
  die "imported keychain has no Mac installer identity (3rd Party Mac Developer Installer or Mac Installer Distribution)"
fi
log "Apple Distribution and Mac installer identities imported"
log "ASC env written (key id length ${#ASC_KEY_ID})"
