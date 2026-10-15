#!/usr/bin/env bash
# Fail an Apple build whose Info.plist still contains an unsubstituted
# Sentry DSN.  Empty is allowed: telemetry stays dark when the secret is
# unset.  Never print the DSN value.
#
# Usage:
#   scripts/ios-fleet/check-built-sentry-dsn.sh .build/DerivedData
#   scripts/ios-fleet/check-built-sentry-dsn.sh --self-test
set -euo pipefail

sentry_dsn_status() {
  local value="$1"
  if [[ "$value" == *'$('* || "$value" == *'${'* ]]; then
    printf 'placeholder\n'
    return 0
  fi
  if [[ -z "$value" ]]; then
    printf 'absent\n'
    return 0
  fi
  printf 'present\n'
}

self_test() {
  [[ "$(sentry_dsn_status '$(SENTRY_DSN)')" == "placeholder" ]]
  [[ "$(sentry_dsn_status '${SENTRY_DSN}')" == "placeholder" ]]
  [[ "$(sentry_dsn_status 'https://$(SENTRY_DSN)@example/1')" == "placeholder" ]]
  [[ "$(sentry_dsn_status '')" == "absent" ]]
  [[ "$(sentry_dsn_status 'https://public@example.ingest.sentry.io/1')" == "present" ]]
  printf 'check-built-sentry-dsn: self-test ok\n'
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

root="${1:-.build/DerivedData}"
found=0
fail=0

while IFS= read -r plist; do
  [[ -n "$plist" ]] || continue
  found=1
  if ! value="$(/usr/libexec/PlistBuddy -c 'Print :SENTRY_DSN' "$plist" 2>/dev/null)"; then
    printf 'built Info.plist has no SENTRY_DSN key: %s\n' "$plist" >&2
    fail=1
    continue
  fi
  status="$(sentry_dsn_status "$value")"
  unset value
  case "$status" in
    placeholder)
      printf 'SENTRY_DSN is an unresolved placeholder in %s\n' "$plist" >&2
      fail=1
      ;;
    absent)
      printf 'SENTRY_DSN absent in %s; telemetry stays dark\n' "$plist"
      ;;
    present)
      printf 'SENTRY_DSN present in %s (value not printed)\n' "$plist"
      ;;
    *)
      printf 'unexpected DSN status for %s\n' "$plist" >&2
      fail=1
      ;;
  esac
done < <(find "$root" -path '*.app/Info.plist' -print)

if [[ "$found" -eq 0 ]]; then
  printf 'no built Info.plist under %s\n' "$root" >&2
  exit 1
fi
exit "$fail"
