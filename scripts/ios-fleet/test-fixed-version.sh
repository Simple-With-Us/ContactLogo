#!/usr/bin/env bash
# Fixed-version shared merge-timestamp build: merge_stamp, asc_next_shared_build,
# asc_platform_max_build and fixed_build_override_ok in ship-testflight.sh.
# Fully offline: curl and the App Store Connect client are stubs, the registry
# is a fixture, the merge stamp comes from a throwaway git repo with a fixed
# committer date, and credentials are dummy values.
#
# Covers the review rounds: the appcast fetch is https-only, time- and
# size-bounded, and a feed failure (or an appcast with no numeric
# <sparkle:version>, or a floor that is not a positive integer of at most 18
# digits) fails closed with the feed URL in the message; four-digit and
# timestamp floors both join now (the old 1..9998 cap is gone); whitespace
# around the digits is allowed and the max is computed with POSIX tools; a
# non-https feed is refused before curl runs; the paired bundle id passes
# through (pairedBundleId preferred, macBundleId as an alias, a macOS entry
# with neither key pairs with the iOS entry its key names, else with the entry
# whose paired key names this entry); the planner's answer must be a 12-digit
# merge-timestamp build; the merge stamp is the HEAD committer date in
# America/Chicago as YYYYMMDDHHMM; the helpers fail closed without credentials
# and never resolve them themselves (load_secrets in a $(...) subshell would
# leak its temp key dir); a fixed --build must be 12 digits and above THIS
# platform's max (the paired platform may reuse the same value).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${here}/ship-testflight.sh"
tmp="$(mktemp -d)"
real_home="${HOME}"
trap 'HOME="$real_home" rm -rf "$tmp"' EXIT
export HOME="${tmp}/home"
export TMPDIR="${tmp}/tmp"
mkdir -p "$HOME" "$TMPDIR" "${tmp}/bin"

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- throwaway git repo with a fixed committer date ---------------------------
# 2026-10-29 00:00 -05:00 is 202610290000 in America/Chicago (CDT).  The stamp
# is read with the exact production command, then pinned to the literal so a
# zone-data surprise fails loudly instead of drifting the assertions below.
GITREPO="${tmp}/gitrepo"
git -c init.defaultBranch=main init -q "$GITREPO"
echo x > "${GITREPO}/f"
git -C "$GITREPO" add f
GIT_AUTHOR_DATE="2026-10-29T00:00:00-05:00" GIT_COMMITTER_DATE="2026-10-29T00:00:00-05:00" \
  git -C "$GITREPO" -c user.email=t@t.invalid -c user.name=t -c commit.gpgsign=false commit -qm init
STAMP="$(TZ=America/Chicago git -C "$GITREPO" show -s --format=%cd --date=format-local:%Y%m%d%H%M HEAD)"
[[ "$STAMP" == "202610290000" ]] || fail "fixture stamp is $STAMP, want 202610290000"

# --- fixture registry -------------------------------------------------------
APPS_JSON="${tmp}/apps.json"
cat > "$APPS_JSON" <<'JSON'
{
  "teamId": "TEST",
  "apps": {
    "feedapp": {"bundleId": "com.example.feed", "platform": "iOS", "pairedBuildFeed": "https://example.invalid/appcast.xml"},
    "httpfeed": {"bundleId": "com.example.http", "platform": "iOS", "pairedBuildFeed": "http://example.invalid/appcast.xml"},
    "revios": {"bundleId": "com.example.rev.ios", "platform": "iOS", "pairedBundleId": "com.example.rev.mac"},
    "revmac": {"bundleId": "com.example.rev.mac", "platform": "macOS"},
    "pairios": {"bundleId": "com.example.pairios", "platform": "iOS", "pairedBundleId": "com.example.pairmac"},
    "aliasios": {"bundleId": "com.example.aliasios", "platform": "iOS", "macBundleId": "com.example.aliasmac"},
    "bothios": {"bundleId": "com.example.bothios", "platform": "iOS", "pairedBundleId": "com.example.pref", "macBundleId": "com.example.alias"},
    "wl": {"bundleId": "com.example.wl", "platform": "iOS"},
    "wl-mac": {"bundleId": "com.example.wl.mac", "platform": "macOS"},
    "wx": {"bundleId": "com.example.wx", "platform": "iOS"},
    "wx-mac": {"bundleId": "com.example.wx.mac", "platform": "macOS", "pairedBundleId": "com.example.explicit"},
    "lonely-mac": {"bundleId": "com.example.lonely.mac", "platform": "macOS"}
  }
}
JSON

# --- stub curl (first on PATH) ----------------------------------------------
export CURL_ARGS_LOG="${tmp}/curl-args.log"
export CURL_MODE="ok"
export APPCAST_OK="${tmp}/appcast-ok.xml"
export APPCAST_NONNUM="${tmp}/appcast-nonnum.xml"
export APPCAST_PADDED="${tmp}/appcast-padded.xml"
export APPCAST_TOOLARGE="${tmp}/appcast-toolarge.xml"
export APPCAST_HUGE="${tmp}/appcast-huge.xml"
export APPCAST_ZERO="${tmp}/appcast-zero.xml"
export APPCAST_LONG="${tmp}/appcast-long.xml"
: > "$CURL_ARGS_LOG"
cat > "$APPCAST_OK" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss><channel>
<item><title>1.1.2 (1350)</title><sparkle:version>1350</sparkle:version></item>
<item><title>1.1.2 (1400)</title><sparkle:version>1400</sparkle:version></item>
</channel></rss>
XML
cat > "$APPCAST_NONNUM" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss><channel>
<item><title>1.1.2</title><sparkle:version>1.2.3</sparkle:version></item>
</channel></rss>
XML
cat > "$APPCAST_PADDED" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss><channel>
<item><title>1.1.2 (1350)</title><sparkle:version>  1350  </sparkle:version></item>
<item><title>1.1.2 (1400)</title><sparkle:version>	1400	</sparkle:version></item>
</channel></rss>
XML
cat > "$APPCAST_TOOLARGE" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss><channel>
<item><title>1.1.2 (1400)</title><sparkle:version>1400</sparkle:version></item>
<item><title>1.1.2 (9999)</title><sparkle:version>9999</sparkle:version></item>
</channel></rss>
XML
cat > "$APPCAST_HUGE" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss><channel>
<item><title>1.1.2</title><sparkle:version>202610190645</sparkle:version></item>
</channel></rss>
XML
cat > "$APPCAST_ZERO" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss><channel>
<item><title>1.1.2</title><sparkle:version>0</sparkle:version></item>
</channel></rss>
XML
cat > "$APPCAST_LONG" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss><channel>
<item><title>1.1.2</title><sparkle:version>1234567890123456789</sparkle:version></item>
</channel></rss>
XML
cat > "${tmp}/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_ARGS_LOG"
case "${CURL_MODE:-ok}" in
  fail) echo "curl: (28) Connection timed out" >&2; exit 28 ;;
  empty) printf ''; exit 0 ;;
  nonnumeric) cat "$APPCAST_NONNUM"; exit 0 ;;
  padded) cat "$APPCAST_PADDED"; exit 0 ;;
  toolarge) cat "$APPCAST_TOOLARGE"; exit 0 ;;
  huge) cat "$APPCAST_HUGE"; exit 0 ;;
  zero) cat "$APPCAST_ZERO"; exit 0 ;;
  long) cat "$APPCAST_LONG"; exit 0 ;;
  *) cat "$APPCAST_OK"; exit 0 ;;
esac
STUB
chmod +x "${tmp}/bin/curl"
export PATH="${tmp}/bin:${PATH}"

# --- the real helpers plus a stub ASC client ----------------------------------
funcs="${tmp}/funcs.sh"
{
  echo 'logerr() { echo "[ios-ship] $*" >&2; }'
  echo "APPS_JSON=\"${tmp}/apps.json\""
  echo "REPO_ROOT=\"${tmp}/gitrepo\""
  echo 'ASC_NODE="node"'
  echo "ASC_CALL_LOG=\"${tmp}/asc-calls.log\""
  cat <<'STUB'
asc_client() {
  printf "%s\n" "$*" >> "$ASC_CALL_LOG"
  if [[ "${1:-}" == "max-build" ]]; then
    case "${MAX_BUILD_MODE:-ok}" in
      bad) printf "oops"; return 0 ;;
      fail) return 1 ;;
    esac
    case "${3:-}" in
      IOS) printf "%s" "${MAX_IOS:-0}" ;;
      MAC_OS) printf "%s" "${MAX_MAC:-0}" ;;
      *) printf "0" ;;
    esac
    return 0
  fi
  printf "%s" "${STUB_PLANNED:-202610290123}"
  return 0
}
STUB
  awk '
    /^json_get\(\) \{/ || /^json_paired_referrer\(\) \{/ || /^merge_stamp\(\) \{/ || /^int_gt\(\) \{/ || /^asc_next_shared_build\(\) \{/ || /^asc_platform_max_build\(\) \{/ || /^fixed_build_override_ok\(\) \{/ { grab = 1 }
    grab { print }
    grab && /^\}/ { grab = 0 }
  ' "$script"
} > "$funcs"
grep -q '^asc_next_shared_build()' "$funcs" || fail "asc_next_shared_build not found in ship-testflight.sh"
grep -q '^json_get()' "$funcs" || fail "json_get not found in ship-testflight.sh"
grep -q '^json_paired_referrer()' "$funcs" || fail "json_paired_referrer not found in ship-testflight.sh"
grep -q '^merge_stamp()' "$funcs" || fail "merge_stamp not found in ship-testflight.sh"
grep -q '^int_gt()' "$funcs" || fail "int_gt not found in ship-testflight.sh"
grep -q '^asc_platform_max_build()' "$funcs" || fail "asc_platform_max_build not found in ship-testflight.sh"
grep -q '^fixed_build_override_ok()' "$funcs" || fail "fixed_build_override_ok not found in ship-testflight.sh"
# The helpers run inside $(...):  resolving the credential there would leak
# the temp key dir, so the call must not be in any helper at all.
if grep -n "load_secrets" "$funcs" >/dev/null; then
  fail "a helper still calls load_secrets"
fi

: > "${tmp}/asc-calls.log"

# run_helper <app_key> <bundle_id> <platform> [curl_mode]
# Sets OUT (stdout), RC, ERR (stderr file).  Dummy credentials stay exported
# unless the case unsets them first.
run_helper() {
  local err="${tmp}/helper.err"
  : > "$err"
  OUT=""
  set +e
  OUT="$(APP_KEY="$1" BUNDLE_ID="$2" PLATFORM="$3" CURL_MODE="${4:-ok}" \
    bash -c 'source "'"$funcs"'"; asc_next_shared_build' 2>"$err")"
  RC=$?
  set -e
  ERR="$err"
}

# run_max <bundle_id> <asc_platform>: a direct asc_platform_max_build call.
# Sets MOUT (stdout), MRC, MERR (stderr file).
run_max() {
  local err="${tmp}/max.err"
  : > "$err"
  MOUT=""
  set +e
  MOUT="$(BUNDLE_ID="$1" ASC_PLATFORM="$2" \
    bash -c 'source "'"$funcs"'"; asc_platform_max_build' 2>"$err")"
  MRC=$?
  set -e
  MERR="$err"
}

# run_fixed <want> <bundle_id> <asc_platform>: a direct
# fixed_build_override_ok call.  Sets FRC, FERR (stderr file).
run_fixed() {
  local err="${tmp}/fixed.err"
  : > "$err"
  set +e
  BUNDLE_ID="$2" ASC_PLATFORM="$3" \
    bash -c 'source "'"$funcs"'"; fixed_build_override_ok "$1"' _ "$1" 2>"$err"
  FRC=$?
  set -e
  FERR="$err"
}

# run_lookup <apps_json> <bundle_id>: a direct json_paired_referrer call
# against the given registry.  Sets LOUT (stdout), LRC, LERR (stderr file).
run_lookup() {
  local err="${tmp}/lookup.err"
  : > "$err"
  LOUT=""
  set +e
  LOUT="$(bash -c 'source "'"$funcs"'"; APPS_JSON="$1"; json_paired_referrer "$2"' _ "$1" "$2" 2>"$err")"
  LRC=$?
  set -e
  LERR="$err"
}

export ASC_KEY_ID="dummy-key" ASC_ISSUER_ID="dummy-issuer" ASC_KEY_P8="dummy-pem"
export STUB_PLANNED="202610290123"

# 1. Feed ok:  curl is https-only, time- and size-bounded, the max
# sparkle:version joins as a floor, and the merge stamp reaches the planner.
run_helper feedapp com.example.feed iOS ok
[[ "$RC" -eq 0 && "$OUT" == "202610290123" ]] || fail "feed ok: rc=$RC out=$OUT"
grep -q -- "--connect-timeout 10 --max-time 30" "$CURL_ARGS_LOG" \
  || fail "curl was not time-bounded: $(cat "$CURL_ARGS_LOG")"
grep -q -- "--proto =https --proto-redir =https" "$CURL_ARGS_LOG" \
  || fail "curl was not https-pinned: $(cat "$CURL_ARGS_LOG")"
grep -q -- "--max-filesize 5000000" "$CURL_ARGS_LOG" \
  || fail "curl was not size-bounded: $(cat "$CURL_ARGS_LOG")"
grep -q "https://example.invalid/appcast.xml" "$CURL_ARGS_LOG" \
  || fail "curl was not asked for the feed"
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "plan-release-build com.example.feed 1400 --merge-stamp $STAMP" ]] \
  || fail "floor 1400 / stamp $STAMP did not reach the client: $(tail -1 "${tmp}/asc-calls.log")"

# 2. Feed fetch failure (a timeout here) fails closed with the URL and curl's
# own error, and the ASC client is never reached.
: > "${tmp}/asc-calls.log"
run_helper feedapp com.example.feed iOS fail
[[ "$RC" -eq 1 && -z "$OUT" ]] || fail "feed failure did not fail closed: rc=$RC out=$OUT"
grep -q "https://example.invalid/appcast.xml" "$ERR" || fail "feed URL missing from: $(cat "$ERR")"
grep -q "timed out" "$ERR" || fail "curl stderr missing from: $(cat "$ERR")"
[[ ! -s "${tmp}/asc-calls.log" ]] || fail "ASC client was reached after a feed failure"

# 3. An appcast with no numeric <sparkle:version> names the URL and says so.
run_helper feedapp com.example.feed iOS nonnumeric
[[ "$RC" -eq 1 && -z "$OUT" ]] || fail "non-numeric feed did not fail closed"
grep -q "https://example.invalid/appcast.xml" "$ERR" || fail "feed URL missing from: $(cat "$ERR")"
grep -q "no numeric" "$ERR" || fail "reason missing from: $(cat "$ERR")"

# 4. An empty feed response fails closed (never "no floor") with the URL
# and the no-numeric-version reason, and the ASC client is never reached.
: > "${tmp}/asc-calls.log"
run_helper feedapp com.example.feed iOS empty
[[ "$RC" -eq 1 && -z "$OUT" ]] || fail "empty feed did not fail closed"
grep -q "https://example.invalid/appcast.xml" "$ERR" || fail "feed URL missing from: $(cat "$ERR")"
grep -q "no numeric" "$ERR" || fail "reason missing from: $(cat "$ERR")"
[[ ! -s "${tmp}/asc-calls.log" ]] || fail "ASC client was reached after an empty feed"

# 5. Paired-bundle passthrough:  preferred key, alias, and preferred-wins.
run_helper pairios com.example.pairios iOS
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "plan-release-build com.example.pairios com.example.pairmac --merge-stamp $STAMP" ]] \
  || fail "pairedBundleId did not pass through: $(tail -1 "${tmp}/asc-calls.log")"
run_helper aliasios com.example.aliasios iOS
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "plan-release-build com.example.aliasios com.example.aliasmac --merge-stamp $STAMP" ]] \
  || fail "macBundleId alias did not pass through: $(tail -1 "${tmp}/asc-calls.log")"
run_helper bothios com.example.bothios iOS
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "plan-release-build com.example.bothios com.example.pref --merge-stamp $STAMP" ]] \
  || fail "pairedBundleId did not win: $(tail -1 "${tmp}/asc-calls.log")"

# 6. A macOS entry with neither key pairs with the iOS entry its key names;
# an explicit key wins, and a macOS entry with no sibling ships unpaired.
run_helper wl-mac com.example.wl.mac macOS
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "plan-release-build com.example.wl.mac com.example.wl --merge-stamp $STAMP" ]] \
  || fail "macOS entry did not pair with its iOS entry: $(tail -1 "${tmp}/asc-calls.log")"
run_helper wx-mac com.example.wx.mac macOS
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "plan-release-build com.example.wx.mac com.example.explicit --merge-stamp $STAMP" ]] \
  || fail "explicit paired id did not win on macOS: $(tail -1 "${tmp}/asc-calls.log")"
run_helper lonely-mac com.example.lonely.mac macOS
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "plan-release-build com.example.lonely.mac --merge-stamp $STAMP" ]] \
  || fail "sibling-less macOS entry mispassed: $(tail -1 "${tmp}/asc-calls.log")"

# 7. No credential anywhere fails closed before any network.
: > "$CURL_ARGS_LOG"
: > "${tmp}/asc-calls.log"
(
  unset ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 APPLE_API_KEY_ID APPLE_API_ISSUER_ID APPLE_API_KEY_P8_BASE64
  OUT2=""
  set +e
  OUT2="$(APP_KEY="pairios" BUNDLE_ID="com.example.pairios" PLATFORM="iOS" \
    bash -c 'source "'"$funcs"'"; asc_next_shared_build' 2>"${tmp}/nocred.err")"
  RC2=$?
  set -e
  [[ "$RC2" -eq 1 && -z "$OUT2" ]] || { echo "FAIL: no-credential run did not fail closed: rc=$RC2 out=$OUT2" >&2; exit 1; }
  grep -q "no App Store Connect credential" "${tmp}/nocred.err" \
    || { echo "FAIL: reason missing: $(cat "${tmp}/nocred.err")" >&2; exit 1; }
)
[[ ! -s "$CURL_ARGS_LOG" && ! -s "${tmp}/asc-calls.log" ]] \
  || fail "a credential-less run reached the network"

# 8. A $(...) call leaks no temp key dir (load_secrets runs in the main shell).
before="$(find "$TMPDIR" -maxdepth 1 -name 'asc-key.*' | wc -l)"
run_helper pairios com.example.pairios iOS
after="$(find "$TMPDIR" -maxdepth 1 -name 'asc-key.*' | wc -l)"
[[ "$before" == "$after" ]] || fail "helper call left a temp key dir behind"

# 9. Whitespace around the digits (spaces on one entry, tabs on the other)
# still scrapes, and the max joins as the floor.
run_helper feedapp com.example.feed iOS padded
[[ "$RC" -eq 0 && "$OUT" == "202610290123" ]] || fail "padded feed: rc=$RC out=$OUT err=$(cat "$ERR")"
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "plan-release-build com.example.feed 1400 --merge-stamp $STAMP" ]] \
  || fail "padded floor 1400 did not reach the client: $(tail -1 "${tmp}/asc-calls.log")"

# 10. A non-https feed is refused before curl runs:  curl never sees it and
# the ASC client is never reached.
: > "$CURL_ARGS_LOG"
: > "${tmp}/asc-calls.log"
run_helper httpfeed com.example.http iOS
[[ "$RC" -eq 1 && -z "$OUT" ]] || fail "non-https feed did not fail closed: rc=$RC out=$OUT"
grep -q "http://example.invalid/appcast.xml" "$ERR" || fail "feed URL missing from: $(cat "$ERR")"
grep -q "non-https" "$ERR" || fail "reason missing from: $(cat "$ERR")"
[[ ! -s "$CURL_ARGS_LOG" ]] || fail "curl ran for a non-https feed"
[[ ! -s "${tmp}/asc-calls.log" ]] || fail "ASC client was reached for a non-https feed"

# 11. The old 1..9998 cap is gone:  a 9999 floor and a timestamp floor both
# join the inventory.  A zero floor and a 19-digit floor still fail closed
# with the URL and the range reason; never shipped past.
for mode in toolarge huge; do
  : > "${tmp}/asc-calls.log"
  run_helper feedapp com.example.feed iOS "$mode"
  [[ "$RC" -eq 0 && "$OUT" == "202610290123" ]] || fail "$mode feed did not join: rc=$RC out=$OUT err=$(cat "$ERR")"
done
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "plan-release-build com.example.feed 202610190645 --merge-stamp $STAMP" ]] \
  || fail "timestamp floor did not reach the client: $(tail -1 "${tmp}/asc-calls.log")"
for mode in zero long; do
  : > "${tmp}/asc-calls.log"
  run_helper feedapp com.example.feed iOS "$mode"
  [[ "$RC" -eq 1 && -z "$OUT" ]] || fail "$mode feed did not fail closed: rc=$RC out=$OUT"
  grep -q "https://example.invalid/appcast.xml" "$ERR" || fail "feed URL missing from ($mode): $(cat "$ERR")"
  grep -q "not a positive integer of at most 18 digits" "$ERR" || fail "range reason missing from ($mode): $(cat "$ERR")"
  [[ ! -s "${tmp}/asc-calls.log" ]] || fail "ASC client was reached for an out-of-range floor ($mode)"
done

# 12. macOS reverse lookup:  revmac has neither paired key and its key names
# no sibling ("revmac" is not "*-mac"), but revios points at its bundle id,
# so the iOS bundle id joins as the paired id.
run_helper revmac com.example.rev.mac macOS
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "plan-release-build com.example.rev.mac com.example.rev.ios --merge-stamp $STAMP" ]] \
  || fail "macOS reverse lookup did not pair: $(tail -1 "${tmp}/asc-calls.log")"

# 13. The feed max no longer goes through a hardcoded interpreter:  the
# /usr/bin/python3 -c one-liner is gone (json_get's plain - read stays) and
# POSIX sort picks the max.
if grep -q '/usr/bin/python3 -c' "$funcs"; then
  fail "feed max still uses /usr/bin/python3 -c"
fi
grep -q 'sort -n' "$funcs" || fail "feed max is not computed with POSIX sort"

# 14. No referrer is not an error: the lookup exits 0 with empty output and
# silent stderr, and a macOS entry no other entry names ships unpaired.
run_lookup "$APPS_JSON" "com.example.nobody"
[[ "$LRC" -eq 0 && -z "$LOUT" ]] || fail "no-referrer lookup: rc=$LRC out=$LOUT"
[[ ! -s "$LERR" ]] || fail "no-referrer lookup wrote to stderr: $(cat "$LERR")"
: > "${tmp}/asc-calls.log"
run_helper lonely-mac com.example.lonely.mac macOS
[[ "$RC" -eq 0 && "$OUT" == "202610290123" ]] || fail "no-referrer ship did not proceed unpaired: rc=$RC out=$OUT err=$(cat "$ERR")"
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "plan-release-build com.example.lonely.mac --merge-stamp $STAMP" ]] \
  || fail "no-referrer ship mispassed: $(tail -1 "${tmp}/asc-calls.log")"

# 15. A broken registry fails the reverse lookup closed (non-zero exit with
# the reason on stderr), and a macOS ship with no paired key refuses to
# ship unpaired off it: no build is planned and the ASC client is never
# reached.
printf '{ broken json\n' > "${tmp}/apps-broken.json"
cat > "${tmp}/apps-badentry.json" <<'JSON'
{"apps": {"odd": "not-a-dict"}}
JSON
cat > "${tmp}/apps-nobundle.json" <<'JSON'
{"apps": {"x": {"pairedBundleId": "com.example.target"}}}
JSON
run_lookup "${tmp}/apps-broken.json" "com.example.lonely.mac"
[[ "$LRC" -ne 0 && -z "$LOUT" ]] || fail "malformed registry lookup did not fail: rc=$LRC out=$LOUT"
grep -q "cannot parse" "$LERR" || fail "parse reason missing from: $(cat "$LERR")"
run_lookup "${tmp}/apps-badentry.json" "com.example.lonely.mac"
[[ "$LRC" -ne 0 && -z "$LOUT" ]] || fail "malformed-entry lookup did not fail: rc=$LRC out=$LOUT"
grep -q "malformed" "$LERR" || fail "entry reason missing from: $(cat "$LERR")"
run_lookup "${tmp}/apps-missing.json" "com.example.lonely.mac"
[[ "$LRC" -ne 0 && -z "$LOUT" ]] || fail "missing-registry lookup did not fail: rc=$LRC out=$LOUT"
grep -q "cannot read" "$LERR" || fail "read reason missing from: $(cat "$LERR")"
run_lookup "${tmp}/apps-nobundle.json" "com.example.target"
[[ "$LRC" -ne 0 && -z "$LOUT" ]] || fail "bundle-less referrer lookup did not fail: rc=$LRC out=$LOUT"
grep -q "no bundleId" "$LERR" || fail "bundle reason missing from: $(cat "$LERR")"
cp "$APPS_JSON" "${tmp}/apps-good.json"
printf '{ broken json\n' > "$APPS_JSON"
: > "${tmp}/asc-calls.log"
run_helper lonely-mac com.example.lonely.mac macOS
BROKEN_RC="$RC"; BROKEN_OUT="$OUT"; BROKEN_ERR="$(cat "$ERR")"
cp "${tmp}/apps-good.json" "$APPS_JSON"
[[ "$BROKEN_RC" -eq 1 && -z "$BROKEN_OUT" ]] || fail "broken-registry ship did not fail closed: rc=$BROKEN_RC out=$BROKEN_OUT"
printf '%s' "$BROKEN_ERR" | grep -q "paired lookup" || fail "paired-lookup reason missing from: $BROKEN_ERR"
[[ ! -s "${tmp}/asc-calls.log" ]] || fail "ASC client was reached after a broken registry"
# The fixture is restored: the next run pairs again.
run_helper revmac com.example.rev.mac macOS
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "plan-release-build com.example.rev.mac com.example.rev.ios --merge-stamp $STAMP" ]] \
  || fail "fixture was not restored after the broken-registry case"

# 16. The merge stamp is the HEAD committer date in America/Chicago as
# YYYYMMDDHHMM (pinned to the literal at setup).  An unreadable stamp fails
# the plan closed before the ASC client is reached.
GOT_STAMP="$(bash -c 'source "'"$funcs"'"; merge_stamp' 2>"${tmp}/stamp.err")"
[[ "$GOT_STAMP" == "$STAMP" && "$GOT_STAMP" == "202610290000" ]] \
  || fail "merge_stamp printed '$GOT_STAMP', want 202610290000: $(cat "${tmp}/stamp.err")"
mkdir -p "${tmp}/empty"
for badroot in "${tmp}/empty" "${tmp}/does-not-exist"; do
  : > "${tmp}/asc-calls.log"
  OUT=""
  set +e
  OUT="$(APP_KEY="pairios" BUNDLE_ID="com.example.pairios" PLATFORM="iOS" \
    bash -c 'source "'"$funcs"'"; REPO_ROOT="'"$badroot"'"; asc_next_shared_build' 2>"${tmp}/badstamp.err")"
  RC=$?
  set -e
  [[ "$RC" -eq 1 && -z "$OUT" ]] || fail "bad stamp root $badroot did not fail closed: rc=$RC out=$OUT"
  grep -q "merge stamp" "${tmp}/badstamp.err" || fail "stamp reason missing from: $(cat "${tmp}/badstamp.err")"
  [[ ! -s "${tmp}/asc-calls.log" ]] || fail "ASC client was reached with an unreadable stamp ($badroot)"
done

# 17. The planner's answer must be a 12-digit merge-timestamp build:  a
# four-digit answer, a leading-zero answer and a 13-digit answer all fail
# closed with no output.
for badplan in 1501 022610290000 2026102900000; do
  : > "${tmp}/asc-calls.log"
  STUB_PLANNED="$badplan" run_helper pairios com.example.pairios iOS
  [[ "$RC" -eq 1 && -z "$OUT" ]] || fail "planner answer $badplan did not fail closed: rc=$RC out=$OUT"
done

# 18. int_gt compares digit strings, so values past 2^63 compare exactly.
int_case() {
  local want="$1" a="$2" b="$3" rc
  set +e
  bash -c 'source "'"$funcs"'"; int_gt "$1" "$2"' _ "$a" "$b" >/dev/null 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq "$want" ]] || fail "int_gt $a $b exited $rc, want $want"
}
int_case 0 "202610290001" "202610290000"
int_case 0 "99999999999999999999" "99999999999999999998"
int_case 0 "100000000000000000000" "99999999999999999999"
int_case 0 "202610290000" "0"
int_case 1 "202610290000" "202610290000"
int_case 1 "202610290000" "202610290001"
int_case 1 "999" "1000"
int_case 1 "abc" "0"
int_case 1 "202610290000" "abc"
int_case 1 "" ""

# 19. A fixed --build must be 12 digits and above THIS platform's max.  The
# paired platform may reuse the same value:  202610290005 ships on iOS here
# even though it equals the mac max, because the iOS max is lower and only
# the iOS inventory is consulted.
export MAX_IOS="202610290000" MAX_MAC="202610290005" MAX_BUILD_MODE="ok"
: > "${tmp}/asc-calls.log"
run_fixed "202610290005" com.example.pairios IOS
[[ "$FRC" -eq 0 ]] || fail "paired-equal build rejected: rc=$FRC err=$(cat "$FERR")"
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "max-build com.example.pairios IOS" ]] \
  || fail "this platform's max was not consulted: $(cat "${tmp}/asc-calls.log")"
run_fixed "202610290000" com.example.pairios IOS
[[ "$FRC" -eq 1 ]] || fail "build equal to this platform's max was accepted"
grep -q "not above" "$FERR" || fail "reason missing from: $(cat "$FERR")"
run_fixed "202610280000" com.example.pairios IOS
[[ "$FRC" -eq 1 ]] || fail "build below this platform's max was accepted"
for badbuild in 1501 999 022610290000 2026102900000 "" "202610290000.1" "v1"; do
  run_fixed "$badbuild" com.example.pairios IOS
  [[ "$FRC" -eq 1 ]] || fail "malformed build '$badbuild' was accepted"
  grep -q "12-digit" "$FERR" || fail "shape reason missing for '$badbuild': $(cat "$FERR")"
done
# The mac platform asks for its own max.
: > "${tmp}/asc-calls.log"
run_fixed "202610290006" com.example.wl.mac MAC_OS
[[ "$FRC" -eq 0 ]] || fail "mac build rejected: rc=$FRC err=$(cat "$FERR")"
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "max-build com.example.wl.mac MAC_OS" ]] \
  || fail "mac max was not consulted: $(cat "${tmp}/asc-calls.log")"
# Without credentials the max is unverifiable, so the build is refused.
(
  unset ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 APPLE_API_KEY_ID APPLE_API_ISSUER_ID APPLE_API_KEY_P8_BASE64
  set +e
  BUNDLE_ID="com.example.pairios" ASC_PLATFORM="IOS" \
    bash -c 'source "'"$funcs"'"; fixed_build_override_ok "202610290005"' 2>"${tmp}/fixednocred.err"
  FRC2=$?
  set -e
  [[ "$FRC2" -eq 1 ]] || { echo "FAIL: credential-less --build was accepted" >&2; exit 1; }
  grep -q "credential" "${tmp}/fixednocred.err" \
    || { echo "FAIL: reason missing: $(cat "${tmp}/fixednocred.err")" >&2; exit 1; }
)

# 20. asc_platform_max_build prints the max, or 0 when the platform has no
# build yet; a malformed or failed answer fails closed with no output.
export MAX_IOS="202610290000" MAX_BUILD_MODE="ok"
run_max com.example.pairios IOS
[[ "$MRC" -eq 0 && "$MOUT" == "202610290000" ]] || fail "max read: rc=$MRC out=$MOUT err=$(cat "$MERR")"
export MAX_IOS="0"
run_max com.example.pairios IOS
[[ "$MRC" -eq 0 && "$MOUT" == "0" ]] || fail "empty platform did not print 0: rc=$MRC out=$MOUT"
export MAX_BUILD_MODE="bad"
run_max com.example.pairios IOS
[[ "$MRC" -eq 1 && -z "$MOUT" ]] || fail "malformed max did not fail closed: rc=$MRC out=$MOUT"
export MAX_BUILD_MODE="fail"
run_max com.example.pairios IOS
[[ "$MRC" -eq 1 && -z "$MOUT" ]] || fail "failed max did not fail closed: rc=$MRC out=$MOUT"
export MAX_BUILD_MODE="ok"

echo "ok: fixed-version merge-timestamp build (bounded https-only feed, whitespace-tolerant scrape, 18-digit floor, paired passthrough incl. macOS reverse lookup, 12-digit planner answer, git merge stamp, this-platform --build validation, credentials fail closed)"
