#!/usr/bin/env bash
# --plan-build-only prints exactly the planned build on stdout: no Xcode tool
# output may leak into it.  Regression test for the DEVELOPER_DIR sanity check
# that ran `xcodebuild -version` before the plan-build early exit, corrupting
# the single build number the release workflow captures.  Fully offline: the
# App Store Connect client is a stub, the merge stamp comes from a throwaway
# git repo with a fixed committer date, and the ASC credential is a throwaway
# key generated for this run (never committed, never a real secret).
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
# 2026-10-29 00:00 -05:00 is 202610290000 in America/Chicago (CDT).
GITREPO="${tmp}/gitrepo"
git -c init.defaultBranch=main init -q "$GITREPO"
echo x > "${GITREPO}/f"
git -C "$GITREPO" add f
GIT_AUTHOR_DATE="2026-10-29T00:00:00-05:00" GIT_COMMITTER_DATE="2026-10-29T00:00:00-05:00" \
  git -C "$GITREPO" -c user.email=t@t.invalid -c user.name=t -c commit.gpgsign=false commit -qm init

# --- throwaway ASC credential (generated, never a real secret) ------------------
# load_secrets only accepts an ambient ASC_KEY_P8 that parses as a PEM private
# key and comes with its key id and issuer.
command -v node >/dev/null 2>&1 || fail "node is required"
export ASC_KEY_ID="TESTKEY123"
export ASC_ISSUER_ID="00000000-0000-0000-0000-000000000000"
export ASC_KEY_P8
ASC_KEY_P8="$(node -e 'console.log(require("node:crypto").generateKeyPairSync("ec",{namedCurve:"P-256"}).privateKey.export({type:"pkcs8",format:"pem"}))')"
[[ -n "$ASC_KEY_P8" ]] || fail "could not generate a throwaway test key"

# --- stub ASC client: answers the planner, logs its calls -----------------------
export STUB_PLANNED="202610290123"
export ASC_CALL_LOG="${tmp}/asc-calls.log"
: > "$ASC_CALL_LOG"
cat > "${tmp}/bin/asc-stub" <<'STUB'
#!/usr/bin/env bash
# argv: <asc-api.mjs path> <command> ...  (asc_client prepends the module path)
printf '%s\n' "$*" >> "$ASC_CALL_LOG"
if [[ "${2:-}" == "plan-release-build" ]]; then
  printf '%s' "${STUB_PLANNED:?}"
  exit 0
fi
echo "asc-stub: unexpected call: $*" >&2
exit 1
STUB
chmod +x "${tmp}/bin/asc-stub"
export IOS_FLEET_NODE="${tmp}/bin/asc-stub"

# --- fake xcodebuild: a macOS runner's version banner on stdout ------------------
# If the plan path ever runs it again, its banner pollutes the captured build
# and the marker proves it ran.
export XCODEBUILD_MARKER="${tmp}/xcodebuild-ran"
cat > "${tmp}/bin/xcodebuild" <<'STUB'
#!/usr/bin/env bash
: > "$XCODEBUILD_MARKER"
echo "Xcode 16.4"
echo "Build version 16F6"
exit 0
STUB
chmod +x "${tmp}/bin/xcodebuild"
export PATH="${tmp}/bin:${PATH}"
# A macOS runner exports DEVELOPER_DIR, which is what armed the sanity check.
export DEVELOPER_DIR="${tmp}/Xcode.app/Contents/Developer"

# --- plan ------------------------------------------------------------------------
out=""
rc=0
err="${tmp}/plan.err"
: > "$err"
set +e
out="$(bash "$script" contactlogo --repo-root "$GITREPO" --plan-build-only 2>"$err")"
rc=$?
set -e

[[ "$rc" -eq 0 ]] || { sed 's/^/  stderr: /' "$err" >&2; fail "plan-build-only exited $rc"; }
[[ "$out" == "$STUB_PLANNED" ]] || fail "plan stdout is not exactly the build: got '${out}' want '${STUB_PLANNED}'"
[[ ! -e "$XCODEBUILD_MARKER" ]] || fail "xcodebuild ran during --plan-build-only"
grep -q "plan-release-build com.contactlogo com.contactlogo.macos --merge-stamp 202610290000" "$ASC_CALL_LOG" \
  || fail "planner was not asked for the paired release build: $(cat "$ASC_CALL_LOG")"
grep -q "using DEVELOPER_DIR=" "$err" || fail "expected the DEVELOPER_DIR diagnostic on stderr"

echo "PASS: --plan-build-only prints exactly the build and never runs xcodebuild"
