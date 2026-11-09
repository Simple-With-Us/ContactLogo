#!/usr/bin/env bash
# OPS-1052: ensure_tf_ready maps asc-api ensure-tf-ready exit codes to distinct
# messages (never label rc=5/6 as generic export-compliance failures).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${here}/ship-testflight.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

extract_ensure() {
  awk '
    /^ensure_tf_ready\(\) \{/ { grab = 1; depth = 0 }
    grab {
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == "{") depth++
        else if (c == "}") depth--
      }
      print
      if (depth == 0) exit
    }
  ' "$script"
}

grep -q '^ensure_tf_ready()' <(extract_ensure) || fail "ensure_tf_ready not found"

run_ready() {
  local mock_rc="$1"
  local out="${tmp}/out-${mock_rc}.log"
  local log_dir="${tmp}/logs-${mock_rc}"
  mkdir -p "$log_dir"
  {
    echo 'log() { echo "[ios-ship] $*"; }'
    echo "FLEET_DIR=\"${here}\""
    echo "BUNDLE_ID=com.contactlogo.test"
    echo "BUILD_NUM=202611091200"
    echo "MARKETING=0.1.0"
    echo "LOG_DIR=\"${log_dir}\""
    echo "REPO_ROOT=\"${tmp}\""
    echo "DISPLAY_NAME=ContactLogo"
    echo "PREV_SHIP_SHA="
    echo "IOS_PATH_PREFIX=apps/ios"
    echo 'asc_client() { printf "{}" >"${LOG_DIR}/ensure-tf-ready.json"; return '"${mock_rc}"'; }'
    extract_ensure
    echo 'ensure_tf_ready'
  } > "${tmp}/harness-${mock_rc}.sh"
  GITHUB_ACTIONS=1 bash "${tmp}/harness-${mock_rc}.sh" >"$out" 2>&1
  printf '%s' "$out"
}

assert_distinct() {
  local rc="$1"
  local needle="$2"
  local forbidden="${3:-}"
  local logfile
  logfile="$(run_ready "$rc")"
  grep -q "$needle" "$logfile" || fail "rc=${rc}: expected log/annotation containing: ${needle}"
  if [[ -n "$forbidden" ]] && grep -q "$forbidden" "$logfile"; then
    fail "rc=${rc}: must not contain: ${forbidden}"
  fi
}

assert_distinct 0 "TestFlight internal testers can install this build" "export compliance"
assert_distinct 3 "has not reached IN_BETA_TESTING" "export compliance"
assert_distinct 4 "ASC never surfaced build" "build may be stuck on export compliance"
assert_distinct 5 "no internal TestFlight testers with access to all builds" "build may be stuck on export compliance"
logfile5="$(run_ready 5)"
grep -q 'external TestFlight' "$logfile5" && fail "rc=5 must not mention external groups (asc-api uses internal tester count)"
assert_distinct 6 "internal TestFlight tester count could not be read" "build may be stuck on export compliance"
logfile6="$(run_ready 6)"
grep -q 'external installability' "$logfile6" && fail "rc=6 must not mention external installability (asc-api uses internal tester count)"
assert_distinct 2 "build may be stuck on export compliance" "no internal TestFlight testers with access to all builds"

out5="$(run_ready 5)"
grep -q '::warning title=TestFlight has no reachable internal tester::' "$out5" || fail "rc=5 missing GitHub annotation"
out6="$(run_ready 6)"
grep -q '::warning title=TestFlight internal installability unverified::' "$out6" || fail "rc=6 missing GitHub annotation"

# Pairwise: no two failure codes share the same primary warning line.
for a in 2 3 4 5 6; do
  for b in 2 3 4 5 6; do
  [[ "$a" -lt "$b" ]] || continue
  line_a="$(grep -E '^\[ios-ship\] warning:' "$(run_ready "$a")" | head -1 || true)"
  line_b="$(grep -E '^\[ios-ship\] warning:' "$(run_ready "$b")" | head -1 || true)"
  [[ -n "$line_a" && -n "$line_b" ]] || fail "missing warning line for rc=${a} or rc=${b}"
  [[ "$line_a" != "$line_b" ]] || fail "rc=${a} and rc=${b} share the same warning line"
  done
done

echo "OK: ensure-tf-ready return codes map to distinct messages"
