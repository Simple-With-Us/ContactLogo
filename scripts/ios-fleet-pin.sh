#!/usr/bin/env bash
# ios-fleet-pin.sh - verify (or refresh) the checksum pin for the in-repo App
# Store ship tooling this repo vendors under scripts/ios-fleet/.
#
# Usage:
#   bash scripts/ios-fleet-pin.sh            # verify; exit 1 on drift
#   bash scripts/ios-fleet-pin.sh --check    # same
#   bash scripts/ios-fleet-pin.sh --update   # rewrite the pin from the in-repo copy
#
# WHY THIS EXISTS
#   GitHub-hosted macos-latest has no /Users/jay/apps/ios-fleet.  This repo
#   vendors the fleet ship tooling (Usage-Monitor, Congress.Trade and
#   Socratic-Trade do the same) and pins its sha256, so an unreviewed edit to
#   ship-testflight.sh, the App Store Connect client, the export options or the
#   ship registry cannot silently change what TestFlight receives.  Refreshing
#   the pin is a reviewed PR.  CI runs this check on every pull request.
#
# The iOS lane (ios-testflight.yml, CL-204) and the Mac lane (mac-testflight.yml,
# CL-203) ship through this one set of files.  ship-testflight.sh is the central
# ios-fleet script plus the ContactLogo deltas listed in its header (the iOS
# archive identity override, and macOS manual signing for contactlogo-mac).
#
# ON DRIFT
#   Read the diff, decide whether the tooling change is wanted, then either
#   revert the fleet files or run --update and land the new pin in a PR.
#   Emergency bypass for a single ship: IOS_FLEET_PIN_SKIP=1.
#
# ASCII-only (Apple bash 3.2 safe).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLEET_DIR="${IOS_FLEET_DIR:-${REPO_ROOT}/scripts/ios-fleet}"
PIN_FILE="${REPO_ROOT}/scripts/ios-fleet.sha256"

# Exactly the files that can change what this repo ships.  The Sentry helper
# scripts in the same directory are ordinary CI scripts and are not pinned.
# asc-key.mjs is pinned since AFC-459:  the App Store Connect credential is
# validated and staged by it, so an unreviewed edit to it decides which key
# the ship runs with.
# version-plan.mjs is pinned since AFC-517:  it holds the version-numbering
# rules (the next patch on the train, the build floor), so an unreviewed edit
# to it decides which version and which build number the ship carries.
# shared-build.mjs is pinned:  it decides the uploaded build in fixed mode
# (the shared merge-timestamp build), like version-plan.mjs.
PINNED_FILES="ship-testflight.sh asc-api.mjs asc-key.mjs apps.json scheduled-ship-gate.sh publish-ios-versions.sh ExportOptions-appstore.plist ExportOptions-export-ipa.plist mac-appstore-profiles.json version-plan.mjs shared-build.mjs"

MODE="check"
case "${1:-}" in
  --update) MODE="update" ;;
  --check|"") MODE="check" ;;
  *) echo "usage: $0 [--check|--update]" >&2; exit 2 ;;
esac

hash_one() {
  # "<sha256>  <name>" for one file, name-only so the pin is path-independent.
  local f="$1"
  [[ -f "${FLEET_DIR}/${f}" ]] || { echo "error: missing ${FLEET_DIR}/${f}" >&2; return 1; }
  if command -v shasum >/dev/null 2>&1; then
    printf '%s  %s\n' "$(shasum -a 256 "${FLEET_DIR}/${f}" | awk '{print $1}')" "$f"
  else
    printf '%s  %s\n' "$(sha256sum "${FLEET_DIR}/${f}" | awk '{print $1}')" "$f"
  fi
}

compute_all() {
  local f
  for f in $PINNED_FILES; do
    hash_one "$f" || return 1
  done
}

if [[ "$MODE" == "update" ]]; then
  {
    echo "# sha256 pin for the in-repo App Store ship tooling in scripts/ios-fleet."
    echo "# GitHub-hosted macos-latest ships from this copy, not /Users/jay/apps/ios-fleet."
    echo "# Refresh with: bash scripts/ios-fleet-pin.sh --update  (then land it in a PR)"
    compute_all
  } >"$PIN_FILE"
  echo "[ios-fleet-pin] wrote ${PIN_FILE}"
  exit 0
fi

if [[ -n "${IOS_FLEET_PIN_SKIP:-}" ]]; then
  echo "[ios-fleet-pin] IOS_FLEET_PIN_SKIP set - skipping the drift check for this run"
  exit 0
fi

if [[ ! -f "$PIN_FILE" ]]; then
  echo "error: pin file missing: ${PIN_FILE}" >&2
  echo "       create it with: bash scripts/ios-fleet-pin.sh --update" >&2
  exit 1
fi

EXPECTED="$(grep -v '^#' "$PIN_FILE" | sed '/^$/d')"
ACTUAL="$(compute_all)" || exit 1

if [[ "$EXPECTED" == "$ACTUAL" ]]; then
  echo "[ios-fleet-pin] OK - ${FLEET_DIR} matches scripts/ios-fleet.sha256"
  exit 0
fi

echo "error: in-repo App Store ship tooling has drifted from this repo's pin." >&2
echo "  fleet dir: ${FLEET_DIR}" >&2
echo "  pin file:  scripts/ios-fleet.sha256" >&2
echo "" >&2
echo "  expected:" >&2
printf '%s\n' "$EXPECTED" | sed 's/^/    /' >&2
echo "  actual:" >&2
printf '%s\n' "$ACTUAL" | sed 's/^/    /' >&2
echo "" >&2
echo "  Review the change, then either revert it or accept it with:" >&2
echo "    bash scripts/ios-fleet-pin.sh --update && git commit -am 'chore(ios): refresh ios-fleet pin'" >&2
echo "  Emergency single-ship bypass: IOS_FLEET_PIN_SKIP=1" >&2
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  echo "::error::ios-fleet tooling drifted from scripts/ios-fleet.sha256 - review and refresh the pin"
fi
exit 1
