#!/usr/bin/env bash
# Thin wrapper: ship the ContactLogo iOS app to TestFlight (no Xcode UI).
# Canonical implementation: scripts/ios-fleet/ship-testflight.sh (in this repo,
# a vendored copy of the fleet script).  A GitHub-hosted macOS runner has no
# /Users/jay/apps/ios-fleet; that path is a local fallback only.
#
# WHY A MERGE OFTEN DOES NOT PRODUCE A TESTFLIGHT BUILD
# .github/workflows/ios-testflight.yml calls this on every push to main that
# touches the iOS tree, but the fleet script keeps two defaults on purpose:  a
# minimum interval between successful ships per app (DEFAULT_MIN_INTERVAL_SEC
# near the top of scripts/ios-fleet/ship-testflight.sh), and a skip when git
# HEAD already shipped.  Runs inside the window log "ship-gate: skip" and exit 0
# without consuming a build number.  The scheduled catch-up in the workflow
# ships a merge that landed inside the window on a later tick.
# Override ONE run with --force-ship or IOS_TF_MIN_INTERVAL_SEC=<seconds>;
# never set either as a standing value in a workflow.
#
# STABLE XCODE IS MANDATORY.  A binary built against a beta SDK is accepted into
# TestFlight and then rejected at submission as INVALID_BINARY.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

IN_REPO="${ROOT}/scripts/ios-fleet/ship-testflight.sh"
HOST_COPY="/Users/jay/apps/ios-fleet/ship-testflight.sh"
if [[ -f "$IN_REPO" ]]; then
  SHIP_SCRIPT="$IN_REPO"
  echo "[ios-ship] using in-repo fleet script: ${SHIP_SCRIPT}"
elif [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  echo "error: hosted runner has no ${HOST_COPY}; vendor scripts/ios-fleet/" >&2
  exit 1
elif [[ -f "$HOST_COPY" ]]; then
  echo "[ios-ship] WARNING: in-repo fleet script missing; using host copy" >&2
  SHIP_SCRIPT="$HOST_COPY"
else
  echo "error: no ship-testflight.sh (looked at ${IN_REPO})" >&2
  exit 1
fi
exec bash "$SHIP_SCRIPT" contactlogo --repo-root "$ROOT" "$@"
