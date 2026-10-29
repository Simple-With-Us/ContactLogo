#!/usr/bin/env bash
# Fixed-version shared four-digit counter: asc_next_shared_build in
# ship-testflight.sh.  Fully offline:  curl and the App Store Connect client
# are stubs, the registry is a fixture, and credentials are dummy values.
#
# Covers the review rounds:  the appcast fetch is https-only, time- and
# size-bounded, and a feed failure (or an appcast with no numeric
# <sparkle:version>, or a floor outside 1..9998) fails closed with the feed
# URL in the message; whitespace around the digits is allowed and the max is
# computed with POSIX tools; a non-https feed is refused before curl runs;
# the paired bundle id passes through (pairedBundleId preferred, macBundleId
# as an alias, a macOS entry with neither key pairs with the iOS entry its
# key names, else with the entry whose paired key names this entry); the
# helper fails closed without credentials and never resolves them itself
# (load_secrets in a $(...) subshell would leak its temp key dir).
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
  *) cat "$APPCAST_OK"; exit 0 ;;
esac
STUB
chmod +x "${tmp}/bin/curl"
export PATH="${tmp}/bin:${PATH}"

# --- the real helper plus a stub ASC client ----------------------------------
funcs="${tmp}/funcs.sh"
{
  echo 'logerr() { echo "[ios-ship] $*" >&2; }'
  echo "APPS_JSON=\"${tmp}/apps.json\""
  echo 'ASC_NODE="node"'
  echo "ASC_CALL_LOG=\"${tmp}/asc-calls.log\""
  echo 'asc_client() { printf "%s\n" "$*" >> "$ASC_CALL_LOG"; printf "1501"; return 0; }'
  awk '
    /^json_get\(\) \{/ || /^json_paired_referrer\(\) \{/ || /^asc_next_shared_build\(\) \{/ { grab = 1 }
    grab { print }
    grab && /^\}/ { grab = 0 }
  ' "$script"
} > "$funcs"
grep -q '^asc_next_shared_build()' "$funcs" || fail "asc_next_shared_build not found in ship-testflight.sh"
grep -q '^json_get()' "$funcs" || fail "json_get not found in ship-testflight.sh"
grep -q '^json_paired_referrer()' "$funcs" || fail "json_paired_referrer not found in ship-testflight.sh"
# The helper runs inside $(...):  resolving the credential there would leak
# the temp key dir, so the call must not be in the helper at all.
if grep -n "load_secrets" "$funcs" >/dev/null; then
  fail "asc_next_shared_build still calls load_secrets"
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

# 1. Feed ok:  curl is https-only, time- and size-bounded, and the max
# sparkle:version joins as a floor.
run_helper feedapp com.example.feed iOS ok
[[ "$RC" -eq 0 && "$OUT" == "1501" ]] || fail "feed ok: rc=$RC out=$OUT"
grep -q -- "--connect-timeout 10 --max-time 30" "$CURL_ARGS_LOG" \
  || fail "curl was not time-bounded: $(cat "$CURL_ARGS_LOG")"
grep -q -- "--proto =https --proto-redir =https" "$CURL_ARGS_LOG" \
  || fail "curl was not https-pinned: $(cat "$CURL_ARGS_LOG")"
grep -q -- "--max-filesize 5000000" "$CURL_ARGS_LOG" \
  || fail "curl was not size-bounded: $(cat "$CURL_ARGS_LOG")"
grep -q "https://example.invalid/appcast.xml" "$CURL_ARGS_LOG" \
  || fail "curl was not asked for the feed"
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "next-shared-build com.example.feed 1400" ]] \
  || fail "floor 1400 did not reach the client: $(tail -1 "${tmp}/asc-calls.log")"

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
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "next-shared-build com.example.pairios com.example.pairmac" ]] \
  || fail "pairedBundleId did not pass through: $(tail -1 "${tmp}/asc-calls.log")"
run_helper aliasios com.example.aliasios iOS
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "next-shared-build com.example.aliasios com.example.aliasmac" ]] \
  || fail "macBundleId alias did not pass through: $(tail -1 "${tmp}/asc-calls.log")"
run_helper bothios com.example.bothios iOS
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "next-shared-build com.example.bothios com.example.pref" ]] \
  || fail "pairedBundleId did not win: $(tail -1 "${tmp}/asc-calls.log")"

# 6. A macOS entry with neither key pairs with the iOS entry its key names;
# an explicit key wins, and a macOS entry with no sibling ships unpaired.
run_helper wl-mac com.example.wl.mac macOS
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "next-shared-build com.example.wl.mac com.example.wl" ]] \
  || fail "macOS entry did not pair with its iOS entry: $(tail -1 "${tmp}/asc-calls.log")"
run_helper wx-mac com.example.wx.mac macOS
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "next-shared-build com.example.wx.mac com.example.explicit" ]] \
  || fail "explicit paired id did not win on macOS: $(tail -1 "${tmp}/asc-calls.log")"
run_helper lonely-mac com.example.lonely.mac macOS
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "next-shared-build com.example.lonely.mac" ]] \
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
[[ "$RC" -eq 0 && "$OUT" == "1501" ]] || fail "padded feed: rc=$RC out=$OUT err=$(cat "$ERR")"
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "next-shared-build com.example.feed 1400" ]] \
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

# 11. A feed floor outside 1..9998 (9999 here, a timestamp build there)
# fails closed with the URL and the range reason; never ships past it.
for mode in toolarge huge; do
  : > "${tmp}/asc-calls.log"
  run_helper feedapp com.example.feed iOS "$mode"
  [[ "$RC" -eq 1 && -z "$OUT" ]] || fail "$mode feed did not fail closed: rc=$RC out=$OUT"
  grep -q "https://example.invalid/appcast.xml" "$ERR" || fail "feed URL missing from ($mode): $(cat "$ERR")"
  grep -q "outside 1..9998" "$ERR" || fail "range reason missing from ($mode): $(cat "$ERR")"
  [[ ! -s "${tmp}/asc-calls.log" ]] || fail "ASC client was reached for an out-of-range floor ($mode)"
done

# 12. macOS reverse lookup:  revmac has neither paired key and its key names
# no sibling ("revmac" is not "*-mac"), but revios points at its bundle id,
# so the iOS bundle id joins as the paired id.
run_helper revmac com.example.rev.mac macOS
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "next-shared-build com.example.rev.mac com.example.rev.ios" ]] \
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
[[ "$RC" -eq 0 && "$OUT" == "1501" ]] || fail "no-referrer ship did not proceed unpaired: rc=$RC out=$OUT err=$(cat "$ERR")"
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "next-shared-build com.example.lonely.mac" ]] \
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
[[ "$(tail -1 "${tmp}/asc-calls.log")" == "next-shared-build com.example.rev.mac com.example.rev.ios" ]] \
  || fail "fixture was not restored after the broken-registry case"

echo "ok: fixed-version shared build (bounded https-only feed, whitespace-tolerant scrape, range-checked floor, paired passthrough incl. macOS reverse lookup, credentials fail closed)"
