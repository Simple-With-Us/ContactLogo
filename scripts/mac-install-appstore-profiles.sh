#!/usr/bin/env bash
# Download the ContactLogo for Mac App Store provisioning profile over the App
# Store Connect API and install it for MANUAL Release signing.
#
# WHY: Xcode's own provisioning service (developerservices2.apple.com) answers
# the fleet App Store Connect API key with HTTP 401 NOT_AUTHORIZED while
# api.appstoreconnect.apple.com accepts the same key, so a hosted runner cannot
# let `xcodebuild -allowProvisioningUpdates` fetch a profile.  This script
# fetches it with the REST client instead.  Same design as the Socratic-Trade
# and CodeCaps installers.
#
# Map: scripts/ios-fleet/mac-appstore-profiles.json  { "<bundle id>": "<profile name>" }
# The name must equal PROVISIONING_PROFILE_SPECIFIER for the ContactLogoMacAppStore
# target's Release configuration in project.yml.
#
# Checks, all fail closed:
#   - exactly the mapped name, for the mapped bundle id, profileType
#     MAC_APP_STORE, profileState ACTIVE
#   - the profile's application identifier ends with the bundle id
#   - it is a distribution profile (get-task-allow is not true)
#   - when a codesigning identity is installed, one of the profile's
#     certificates is that identity (otherwise the archive fails much later
#     with a vaguer "doesn't include signing certificate" error)
#
# Prints names, bundle ids, UUIDs and certificate SHA-1 fingerprints only.
# Never prints profile bytes or credentials.  ASCII-only (Apple bash 3.2 safe).
#
# To renew an expired or revoked profile, create a new MAC_APP_STORE profile with
# the same name in the developer portal (or POST /v1/profiles through
# scripts/ios-fleet/asc-api.mjs) holding the Apple Distribution and Mac Installer
# Distribution certificates, then re-run the ship.
#
# Env overrides (tests / local use):
#   MAC_APPSTORE_PROFILES_MAP   profile map (default scripts/ios-fleet/mac-appstore-profiles.json)
#   MAC_PROFILES_DIR            install dir (default ~/Library/MobileDevice/Provisioning Profiles)
#   MAC_PROFILE_SKIP_IDENTITY_CHECK=1   skip the keychain certificate match
set +o xtrace
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAP="${MAC_APPSTORE_PROFILES_MAP:-${ROOT}/scripts/ios-fleet/mac-appstore-profiles.json}"
CLIENT="${ROOT}/scripts/ios-fleet/asc-api.mjs"
DEST="${MAC_PROFILES_DIR:-${HOME}/Library/MobileDevice/Provisioning Profiles}"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/cl-mac-profiles.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

[[ -f "$MAP" ]] || { echo "error: profile map missing: $MAP" >&2; exit 1; }
[[ -f "$CLIENT" ]] || { echo "error: App Store Connect client missing: $CLIENT" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "error: node not on PATH" >&2; exit 1; }
command -v security >/dev/null 2>&1 || { echo "error: security(1) not found (macOS only)" >&2; exit 1; }

# Credentials reach asc-api.mjs the way they reach the rest of the fleet ship:
# ship-testflight.sh loads them before it calls this installer, and the client
# reads them from the environment or the file the ship prepared.  This script
# opens no credential file of its own.

mkdir -p "$DEST"

IDENTITIES="$WORKDIR/identities.txt"
: >"$IDENTITIES"
if [[ "${MAC_PROFILE_SKIP_IDENTITY_CHECK:-}" != "1" ]]; then
  # "  1) <SHA-1> "Apple Distribution: ..."" -- fingerprints and names are public.
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/^ *[0-9]+\) ([0-9A-F]{40}) "(.*)"$/\1 \2/p' >"$IDENTITIES" || true
fi

set +e
node "$CLIENT" GET '/v1/profiles?filter[profileType]=MAC_APP_STORE&limit=200&include=bundleId' \
  >"$WORKDIR/profiles.json" 2>"$WORKDIR/profiles.err"
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  # stderr carries only "HTTP <status>" or a stack trace; stdout is Apple's JSON error body.
  status_line="$(grep -m1 -E '^HTTP [0-9]+' "$WORKDIR/profiles.err" || echo 'no HTTP status')"
  code="$(python3 -c 'import json,sys
try:
    e=(json.load(open(sys.argv[1])).get("errors") or [{}])[0]
    print(e.get("code") or e.get("title") or "")
except Exception:
    print("")' "$WORKDIR/profiles.json")"
  echo "error: App Store Connect profile list failed (rc=${rc}, ${status_line}${code:+, ${code}})" >&2
  exit 1
fi

python3 - "$MAP" "$DEST" "$WORKDIR" "$IDENTITIES" <<'PY'
import base64, hashlib, json, os, plistlib, subprocess, sys

want = json.load(open(sys.argv[1], encoding="utf-8"))
dest, workdir, identities_path = sys.argv[2], sys.argv[3], sys.argv[4]
data = json.load(open(os.path.join(workdir, "profiles.json"), encoding="utf-8"))
if data.get("errors"):
    err = data["errors"][0]
    raise SystemExit("error: profile list failed: %s %s" % (err.get("status") or "", err.get("code") or err.get("title") or "unknown"))
if not isinstance(want, dict) or not want:
    raise SystemExit("error: profile map must be a non-empty {bundleId: profileName} object")

identities = {}
for line in open(identities_path, encoding="utf-8"):
    line = line.strip()
    if line:
        sha1, _, name = line.partition(" ")
        identities[sha1.upper()] = name

bundles = {}
for inc in data.get("included") or []:
    if inc.get("type") == "bundleIds":
        bundles[inc["id"]] = (inc.get("attributes") or {}).get("identifier")

found = {}
for row in data.get("data") or []:
    rel = ((row.get("relationships") or {}).get("bundleId") or {}).get("data") or {}
    bid = bundles.get(rel.get("id"))
    attrs = row.get("attributes") or {}
    if bid in want and attrs.get("name") == want[bid] and attrs.get("profileState") == "ACTIVE":
        prev = found.get(bid)
        # Same name twice: keep the one that expires last.
        if prev is None or (attrs.get("expirationDate") or "") > ((prev.get("attributes") or {}).get("expirationDate") or ""):
            found[bid] = row

missing = sorted(bid for bid in want if bid not in found)
if missing:
    raise SystemExit(
        "error: no ACTIVE MAC_APP_STORE profile named as mapped for: %s.  "
        "Create it (developer portal, or POST /v1/profiles through scripts/ios-fleet/asc-api.mjs) "
        "with the Apple Distribution and Mac Installer Distribution certificates CI imports, "
        "or fix scripts/ios-fleet/mac-appstore-profiles.json." % ", ".join(missing))

for bid, row in sorted(found.items()):
    attrs = row.get("attributes") or {}
    name = attrs.get("name")
    blob = base64.b64decode(attrs.get("profileContent") or "")
    if not blob:
        raise SystemExit("error: profile %s has no content" % name)
    raw_path = os.path.join(workdir, bid + ".mobileprovision")
    with open(raw_path, "wb") as handle:
        handle.write(blob)
    os.chmod(raw_path, 0o600)
    plist = plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", raw_path], stderr=subprocess.DEVNULL))
    ents = plist.get("Entitlements") or {}
    app_id = str(ents.get("com.apple.application-identifier") or ents.get("application-identifier") or "")
    if not app_id.endswith("." + bid):
        raise SystemExit("error: profile %s is for %s, not %s" % (name, app_id, bid))
    if ents.get("get-task-allow") is True:
        raise SystemExit("error: profile %s is not a distribution profile (get-task-allow is true)" % name)
    uuid = plist.get("UUID")
    if not uuid:
        raise SystemExit("error: profile %s has no UUID" % name)
    certs = [hashlib.sha1(c).hexdigest().upper() for c in plist.get("DeveloperCertificates") or []]
    if identities:
        hits = [c for c in certs if c in identities]
        if not hits:
            raise SystemExit(
                "error: profile %s does not include any installed codesigning identity.  "
                "Profile certs: %s.  Installed: %s.  Regenerate the profile with the Apple "
                "Distribution certificate that mac-appstore-gm-prepare.sh imports."
                % (name, ", ".join(certs) or "none", ", ".join(sorted(identities)) or "none"))
        print("profile %s matches identity %s (%s)" % (name, hits[0], identities[hits[0]]))
    # Xcode reads .mobileprovision for both platforms from this directory
    # (the CodeCaps Mac ship relies on the same).
    final = os.path.join(dest, uuid + ".mobileprovision")
    os.replace(raw_path, final)
    os.chmod(final, 0o644)
    print("installed %s name=%s uuid=%s expires=%s" % (bid, name, uuid, attrs.get("expirationDate")))
PY
