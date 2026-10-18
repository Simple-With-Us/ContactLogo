#!/usr/bin/env bash
# test-ios-scheduled-ship-gate.sh - Offline tests for ios-scheduled-ship-gate.sh.
#
# The gate is the only thing standing between the scheduled catch-up and a
# TestFlight build for every web, Android or iOS-only commit.  Hosted macos-latest
# is the ship host, so without these tests a defect in it is invisible until
# either testers get spammed or a Mac change silently never ships.  Everything
# here is a throwaway git repo in a scratch dir: no network, no credentials, no
# xcodebuild, no App Store Connect.
#
# Usage: bash scripts/test-ios-scheduled-ship-gate.sh
#
# ASCII-only (Apple bash 3.2 safe).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="${SCRIPT_DIR}/ios-scheduled-ship-gate.sh"
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

# The same source paths the workflow passes.
run_gate() {
  # run_gate <event> [extra args...] -> prints "key=value" lines
  local event="$1"; shift
  bash "$GATE" \
    --event "$event" \
    --path-prefix "Apps/ContactLogoMac/" \
    --path-prefix "Apps/ContactLogoMacAppStore/" \
    --path-prefix "Sources/" \
    --path-prefix "project.yml" \
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

echo "== syntax =="
bash -n "$GATE" && echo "  ok  : ios-scheduled-ship-gate.sh parses"

echo "== fixture =="
BASE="$(commit README.md base "base")"
echo "  base commit ${BASE:0:10}"

echo "== 1. push/dispatch events bypass the gate entirely =="
out="$(run_gate push demo)"
check "push -> should_ship" 1 "$(field "$out" should_ship)"
out="$(run_gate workflow_dispatch demo)"
check "workflow_dispatch -> should_ship" 1 "$(field "$out" should_ship)"

echo "== 2. scheduled tick with no ship history defers to the ship script =="
out="$(run_gate schedule demo)"
check "no state -> should_ship" 1 "$(field "$out" should_ship)"

echo "== 3. scheduled tick on an already-shipped HEAD skips =="
set_state demo "$BASE"
out="$(run_gate schedule demo)"
check "HEAD already shipped -> should_ship" 0 "$(field "$out" should_ship)"

echo "== 4. web, Android, docs and iOS-only commits do NOT ship the Mac app =="
commit "web/src/page.tsx" "web change" "feat(web): unrelated to the Mac app" >/dev/null
commit "docs/notes.md" "docs" "docs: nothing a Mac tester can see" >/dev/null
commit "Apps/ContactLogoAndroid/app/Main.kt" "kt" "feat(android): unrelated" >/dev/null
commit "Apps/ContactLogoiOS/View.swift" "// ios" "fix(ios): an iPhone-only change" >/dev/null
out="$(run_gate schedule demo)"
check "no Mac-app change -> should_ship" 0 "$(field "$out" should_ship)"

echo "== 5. a change under any Mac source path DOES ship =="
commit "Apps/ContactLogoMac/ContentView.swift" "// ui" "fix(mac): visible change" >/dev/null
out="$(run_gate schedule demo)"
check "Apps/ContactLogoMac change -> should_ship" 1 "$(field "$out" should_ship)"

set_state demo "$(git -C "$REPO" rev-parse HEAD)"
commit "Sources/ContactLogoKit/Engine.swift" "// kit" "fix(kit): shared engine" >/dev/null
out="$(run_gate schedule demo)"
check "Sources change -> should_ship" 1 "$(field "$out" should_ship)"

set_state demo "$(git -C "$REPO" rev-parse HEAD)"
commit "project.yml" "name: demo" "build: project spec" >/dev/null
out="$(run_gate schedule demo)"
check "project.yml (a single file path) change -> should_ship" 1 "$(field "$out" should_ship)"

set_state demo "$(git -C "$REPO" rev-parse HEAD)"
commit "Apps/ContactLogoMacAppStore/AutoUpdateStub.swift" "// stub" "fix(mac): store build" >/dev/null
out="$(run_gate schedule demo)"
check "Apps/ContactLogoMacAppStore change -> should_ship" 1 "$(field "$out" should_ship)"

echo "== 6. per-app outputs are independent =="
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"
set_state demo "$HEAD_SHA"          # caught up
set_state demo-two "$BASE"          # behind, and Mac source changed since BASE
out="$(run_gate schedule demo demo-two)"
check "caught-up app" 0 "$(field "$out" ship_demo)"
check "behind app" 1 "$(field "$out" ship_demo_two)"
check "any-app roll-up" 1 "$(field "$out" should_ship)"

echo "== 7. an unreachable last-ship sha falls back to the recorded timestamp =="
# Observed live on Usage-Monitor 2026-08-13: the recorded ship sha was the tip
# of a grok/* ship worktree, not an ancestor of main.  Skipping forever would
# make the backstop useless; shipping blind would spam TestFlight.
rm -f "${STATE}/last-ship-demo-two.txt"
FUTURE=$(( $(date +%s) + 600 ))
printf '%s %s\n' "$FUTURE" "0000000000000000000000000000000000000000" >"${STATE}/last-ship-demo.txt"
out="$(run_gate schedule demo)"
check "unreachable sha, no newer Mac commits -> should_ship" 0 "$(field "$out" should_ship)"

PAST=$(( $(date +%s) - 86400 ))
printf '%s %s\n' "$PAST" "0000000000000000000000000000000000000000" >"${STATE}/last-ship-demo.txt"
out="$(run_gate schedule demo)"
check "unreachable sha, Mac commits since -> should_ship" 1 "$(field "$out" should_ship)"

printf 'not-a-timestamp deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n' >"${STATE}/last-ship-demo.txt"
out="$(run_gate schedule demo)"
check "unreachable sha, unusable ts -> defers to ship script" 1 "$(field "$out" should_ship)"

# Back to a clean skip state for the exit-code assertion below.
set_state demo "$(git -C "$REPO" rev-parse HEAD)"

echo "== 8. deciding 'skip' is never an error exit =="
run_gate schedule demo >/dev/null
check "exit code on skip" 0 "$?"

echo "== 9. a missing --path-prefix is refused =="
bash "$GATE" --event schedule --repo-root "$REPO" --state-dir "$STATE" demo >/dev/null 2>&1
check "no --path-prefix -> exit 2" 2 "$?"

echo
echo "passed=${PASS} failed=${FAIL}"
[[ "$FAIL" -eq 0 ]] || exit 1
echo "scheduled-ship-gate: all tests passed"
