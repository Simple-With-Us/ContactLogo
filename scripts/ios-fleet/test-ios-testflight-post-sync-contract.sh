#!/usr/bin/env bash
# Contract tests for ios-testflight.yml post-sync readiness (OPS-1052).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "${here}/../.." && pwd)"
yml="${repo}/.github/workflows/ios-testflight.yml"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "$yml" ]] || fail "missing ${yml}"

grep -q 'id: ship_testflight' "$yml" || fail "ship step must expose ship_testflight id for uploaded output"
grep -q 'uploaded=' "$yml" || fail "ship step must set uploaded output"
grep -q "steps.ship_testflight.outputs.uploaded == 'true'" "$yml" \
  || fail "post-sync recheck must require uploaded==true"

sync_block="$(awk '/name: Sync standing TestFlight testers/,/name: Re-verify TestFlight readiness/' "$yml")"
grep -q 'if: success()' <<<"$sync_block" || fail "tester sync must stay on success()"

grep -q 'mkdir -p "\$IOS_TF_VERIFY_LOG_DIR"' "$yml" || fail "post-sync step must mkdir before tee"
grep -q 'IOS_TF_READY_POST_SYNC_TIMEOUT_SEC' "$yml" || fail "post-sync must set short timeout env"
grep -q 'exit "\$rc"' "$yml" || fail "post-sync step must exit with verify rc"

summary_block="$(awk '/name: Ship summary/,/name: Drop ship locks/' "$yml")"
grep -q 'grep -E.*\|\| true' <<<"$summary_block" || fail "ship summary grep must tolerate no matches"
grep -q 'log not found' <<<"$summary_block" || fail "ship summary must handle missing post-sync log"

echo "OK: ios-testflight post-sync workflow contract"
