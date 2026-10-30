#!/usr/bin/env bash
# test-ios-scheduled-ship-gate.sh - Offline tests for scripts/ios-fleet/scheduled-ship-gate.sh,
# the gate the TestFlight release workflow and both platform lanes use.
#
# The gate is the only thing standing between the scheduled catch-up and a
# TestFlight build for every web, Android or docs commit -- and, since the
# gates take the release workflow's full on.push.paths list, the reason a
# tooling-only merge a missed push never shipped still goes out on the next
# tick.  Hosted macos-latest is the ship host, so without these tests a defect
# in it is invisible until either testers get spammed or a merge silently
# never ships.  Everything here is a throwaway git repo in a scratch dir: no
# network, no credentials, no xcodebuild, no App Store Connect.
#
# Usage: bash scripts/test-ios-scheduled-ship-gate.sh
#
# ASCII-only (Apple bash 3.2 safe).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="${SCRIPT_DIR}/ios-fleet/scheduled-ship-gate.sh"
[[ -f "$GATE" ]] || { echo "missing $GATE"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ship-gate-test.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

REPO="${TMP}/repo"
STATE="${TMP}/state"
mkdir -p "$REPO" "$STATE"

git -C "$REPO" init --quiet -b main
git -C "$REPO" config user.email "test@example.invalid"
git -C "$REPO" config user.name "gate test"

commit() {
  # commit <path> <content> <message>
  mkdir -p "$(dirname "${REPO}/$1")"
  printf '%s\n' "$2" >"${REPO}/$1"
  git -C "$REPO" add -A
  git -C "$REPO" commit --quiet -m "$3"
  git -C "$REPO" rev-parse HEAD
}

PASS=0
FAIL=0
check() {
  # check <label> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    echo "  ok  : $1 (=$3)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $1 (expected '$2', got '$3')"
    FAIL=$((FAIL + 1))
  fi
}

# The same entries as on.push.paths in .github/workflows/testflight.yml,
# verbatim: globs, exact files, and the '!' exclusions.  The workflow-side
# mirror is enforced by scripts/check-mac-testflight-contract.py, which reads
# the push list out of the workflow file.
run_gate() {
  # run_gate <event> [extra args...] -> prints "key=value" lines
  local event="$1"; shift
  bash "$GATE" \
    --event "$event" \
    --path-prefix "Apps/ContactLogoiOS/**" \
    --path-prefix "Apps/ContactLogoMac/**" \
    --path-prefix "Apps/ContactLogoMacAppStore/**" \
    --path-prefix "Sources/**" \
    --path-prefix "project.yml" \
    --path-prefix ".github/workflows/testflight.yml" \
    --path-prefix ".github/workflows/ios-testflight.yml" \
    --path-prefix ".github/workflows/mac-testflight.yml" \
    --path-prefix ".github/actions/infisical-secrets/**" \
    --path-prefix "scripts/ios-ship-testflight.sh" \
    --path-prefix "scripts/ios-appstore-gm-prepare.sh" \
    --path-prefix "scripts/ios-stage-asc-key.sh" \
    --path-prefix "scripts/ios-collect-ship-logs.sh" \
    --path-prefix "scripts/ios-fleet/**" \
    --path-prefix "scripts/ios-fleet-pin.sh" \
    --path-prefix "scripts/ios-fleet.sha256" \
    --path-prefix "scripts/mac-appstore-gm-prepare.sh" \
    --path-prefix "scripts/mac-export-appstore-pkg.sh" \
    --path-prefix "scripts/mac-install-appstore-profiles.sh" \
    --path-prefix "!scripts/ios-fleet/check-built-sentry-dsn.sh" \
    --path-prefix "!scripts/ios-fleet/upload-sentry-dsyms.sh" \
    --repo-root "$REPO" \
    --state-dir "$STATE" \
    "$@" 2>&1
}

field() {
  # field <output> <key>
  printf '%s\n' "$1" | awk -F= -v k="$2" '$1 == k {print $2}' | tail -1
}

set_state() {
  # set_state <app> <sha>
  printf '%s %s\n' "$(date +%s)" "$2" >"${STATE}/last-ship-$1.txt"
}

ships() {
  # ships <label> <path> <content> -- one commit touching <path> ships.
  set_state demo "$(git -C "$REPO" rev-parse HEAD)"
  commit "$2" "$3" "test: touch $2" >/dev/null
  out="$(run_gate schedule demo)"
  check "$1 -> should_ship" 1 "$(field "$out" should_ship)"
}

echo "== syntax =="
bash -n "$GATE" && echo "  ok  : scripts/ios-fleet/scheduled-ship-gate.sh parses"

echo "== fixture =="
BASE="$(commit README.md base "base")"
echo "  base commit ${BASE:0:10}"

echo "== 1. push/dispatch events bypass the gate entirely =="
out="$(run_gate push demo)"
check "push -> should_ship" 1 "$(field "$out" should_ship)"
out="$(run_gate workflow_dispatch demo)"
check "workflow_dispatch -> should_ship" 1 "$(field "$out" should_ship)"

echo "== 2. scheduled tick with no ship history skips =="
# A hosted runner starts with an empty home, so "no state" would otherwise
# re-archive on every tick.  A first ship is a push that passed the paths filter
# or an explicit dispatch, never the cron.
out="$(run_gate schedule demo)"
check "no state -> should_ship" 0 "$(field "$out" should_ship)"

echo "== 3. scheduled tick on an already-shipped HEAD skips =="
set_state demo "$BASE"
out="$(run_gate schedule demo)"
check "HEAD already shipped -> should_ship" 0 "$(field "$out" should_ship)"

echo "== 4. web, Android, docs, server and README commits do NOT ship =="
commit "web/src/page.tsx" "web change" "feat(web): unrelated to any lane" >/dev/null
commit "docs/notes.md" "docs" "docs: nothing a tester can see" >/dev/null
commit "Apps/ContactLogoAndroid/app/Main.kt" "kt" "feat(android): unrelated" >/dev/null
commit "web/server.mjs" "// server" "fix(server): backend only" >/dev/null
commit "README.md" "base v2" "docs: readme touch-up" >/dev/null
out="$(run_gate schedule demo)"
check "no release-path change -> should_ship" 0 "$(field "$out" should_ship)"

echo "== 5. a change under any push path DOES ship =="
ships "Apps/ContactLogoMac change" "Apps/ContactLogoMac/ContentView.swift" "// ui"
ships "Apps/ContactLogoiOS change" "Apps/ContactLogoiOS/View.swift" "// ios"
ships "Apps/ContactLogoMacAppStore change" "Apps/ContactLogoMacAppStore/AutoUpdateStub.swift" "// stub"
ships "Sources (Kit) change" "Sources/ContactLogoKit/Engine.swift" "// kit"
ships "Sources (non-Kit) change" "Sources/contactlogo/Thing.swift" "// shared"
ships "project.yml (a single file path) change" "project.yml" "name: demo"
ships "scripts/ios-fleet change" "scripts/ios-fleet/ship-testflight.sh" "# fleet ship tooling v1"
ships "workflow file change" ".github/workflows/testflight.yml" "# release workflow v1"
ships "lane workflow change" ".github/workflows/mac-testflight.yml" "# mac lane v1"
ships "mac ship script change" "scripts/mac-export-appstore-pkg.sh" "# mac export v1"
ships "fleet pin script change" "scripts/ios-fleet-pin.sh" "# pin v1"
ships "infisical action change" ".github/actions/infisical-secrets/action.yml" "# action v1"

echo "== 6. the '!' exclusions behave like the push filter =="
# A merge touching ONLY an excluded file fires no push run, so the cron must
# skip it too; an excluded file next to a real change must not hide the change.
set_state demo "$(git -C "$REPO" rev-parse HEAD)"
commit "scripts/ios-fleet/check-built-sentry-dsn.sh" "# sentry check v1" "ci: sentry helper only" >/dev/null
out="$(run_gate schedule demo)"
check "only check-built-sentry-dsn.sh -> should_ship" 0 "$(field "$out" should_ship)"

set_state demo "$(git -C "$REPO" rev-parse HEAD)"
commit "scripts/ios-fleet/upload-sentry-dsyms.sh" "# sentry dsyms v1" "ci: sentry helper only" >/dev/null
out="$(run_gate schedule demo)"
check "only upload-sentry-dsyms.sh -> should_ship" 0 "$(field "$out" should_ship)"

set_state demo "$(git -C "$REPO" rev-parse HEAD)"
commit "scripts/ios-fleet/check-built-sentry-dsn.sh" "# sentry check v2" "ci: sentry helper" >/dev/null
commit "scripts/ios-fleet/ship-testflight.sh" "# fleet ship tooling v2" "fix(ios-fleet): real tooling change" >/dev/null
out="$(run_gate schedule demo)"
check "excluded file plus a real change -> should_ship" 1 "$(field "$out" should_ship)"

echo "== 7. per-app outputs are independent =="
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"
set_state demo "$HEAD_SHA"          # caught up
set_state demo-two "$BASE"          # behind, and release paths changed since BASE
out="$(run_gate schedule demo demo-two)"
check "caught-up app" 0 "$(field "$out" ship_demo)"
check "behind app" 1 "$(field "$out" ship_demo_two)"
check "any-app roll-up" 1 "$(field "$out" should_ship)"

echo "== 8. an unreachable last-ship sha falls back to the recorded timestamp =="
# Observed live on Usage-Monitor 2026-08-13: the recorded ship sha was the tip
# of a grok/* ship worktree, not an ancestor of main.  Skipping forever would
# make the backstop useless; shipping blind would spam TestFlight.
rm -f "${STATE}/last-ship-demo-two.txt"
FUTURE=$(( $(date +%s) + 600 ))
printf '%s %s\n' "$FUTURE" "0000000000000000000000000000000000000000" >"${STATE}/last-ship-demo.txt"
out="$(run_gate schedule demo)"
check "unreachable sha, no newer release-path commits -> should_ship" 0 "$(field "$out" should_ship)"

PAST=$(( $(date +%s) - 86400 ))
printf '%s %s\n' "$PAST" "0000000000000000000000000000000000000000" >"${STATE}/last-ship-demo.txt"
out="$(run_gate schedule demo)"
check "unreachable sha, release-path commits since -> should_ship" 1 "$(field "$out" should_ship)"

printf 'not-a-timestamp deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n' >"${STATE}/last-ship-demo.txt"
out="$(run_gate schedule demo)"
check "unreachable sha, unusable ts -> defers to ship script" 1 "$(field "$out" should_ship)"

# Back to a clean skip state for the exit-code assertion below.
set_state demo "$(git -C "$REPO" rev-parse HEAD)"

echo "== 9. deciding 'skip' is never an error exit =="
run_gate schedule demo >/dev/null
check "exit code on skip" 0 "$?"

echo "== 10. a missing --path-prefix is refused =="
bash "$GATE" --event schedule --repo-root "$REPO" --state-dir "$STATE" demo >/dev/null 2>&1
check "no --path-prefix -> exit 2" 2 "$?"
bash "$GATE" --event schedule --path-prefix '!' --repo-root "$REPO" --state-dir "$STATE" demo >/dev/null 2>&1
check "bare '!' exclusion -> exit 2" 2 "$?"

echo "== 11. the old single-prefix call keeps working =="
set_state demo "$(git -C "$REPO" rev-parse HEAD)"
commit "scripts/ios-fleet/ship-testflight.sh" "# fleet ship tooling v3" "fix(ios-fleet): tooling only" >/dev/null
out="$(bash "$GATE" --event schedule --path-prefix 'Apps/ContactLogoMac/' --repo-root "$REPO" --state-dir "$STATE" demo 2>&1)"
check "single prefix, no match -> should_ship" 0 "$(field "$out" should_ship)"
commit "Apps/ContactLogoMac/ContentView.swift" "// ui v2" "fix(mac): visible change" >/dev/null
out="$(bash "$GATE" --event schedule --path-prefix 'Apps/ContactLogoMac/' --repo-root "$REPO" --state-dir "$STATE" demo 2>&1)"
check "single prefix, match -> should_ship" 1 "$(field "$out" should_ship)"

echo
echo "passed=${PASS} failed=${FAIL}"
[[ "$FAIL" -eq 0 ]] || exit 1
echo "scheduled-ship-gate: all tests passed"
