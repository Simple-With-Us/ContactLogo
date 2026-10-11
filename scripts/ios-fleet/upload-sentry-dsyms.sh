#!/usr/bin/env bash
# Port of ios-fleet/ship-testflight.sh upload_sentry_artifacts for ContactLogo.
#
# Uploads dSYMs / xcarchive debug files to Sentry org simple-with-us.
# Never prints secret values.  Missing token or empty search skips (exit 0)
# so a TestFlight / CI ship is never blocked by Sentry.
#
# Usage:
#   scripts/ios-fleet/upload-sentry-dsyms.sh --app contactlogo --search .build/DerivedData
#   scripts/ios-fleet/upload-sentry-dsyms.sh --app contactlogo-mac --archive path/to.xcarchive
#
# Env (names only):
#   SENTRY_AUTH_TOKEN  org/project:releases (Actions / Infisical / ~/.secrets)
#   SENTRY_ORG         default simple-with-us
set -euo pipefail

APP_KEY=""
SEARCH_DIR=""
ARCHIVE_PATH=""
LOG_DIR="${LOG_DIR:-.build/sentry-logs}"

log() {
  printf 'sentry-dsym: %s\n' "$*"
}

sentry_project_for_app() {
  case "${APP_KEY}" in
    contactlogo) echo "contactlogo" ;;
    contactlogo-mac) echo "contactlogo-macos" ;;
    *) echo "" ;;
  esac
}

load_sentry_auth() {
  if [[ -n "${SENTRY_AUTH_TOKEN:-}" ]]; then
    return 0
  fi
  local keys="${HOME}/.secrets/global-api-keys"
  if [[ -f "$keys" ]]; then
    SENTRY_AUTH_TOKEN="$(grep -m1 '^SENTRY_AUTH_TOKEN=' "$keys" | cut -d= -f2- | tr -d '"' | tr -d '\r' || true)"
    export SENTRY_AUTH_TOKEN
  fi
}

usage() {
  echo "usage: $0 --app contactlogo|contactlogo-mac [--search DIR] [--archive XCARCHIVE]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP_KEY="${2:-}"; shift 2 ;;
    --search) SEARCH_DIR="${2:-}"; shift 2 ;;
    --archive) ARCHIVE_PATH="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

if [[ -z "$APP_KEY" ]]; then
  usage
fi

project="$(sentry_project_for_app)"
if [[ -z "$project" ]]; then
  log "no project mapping for app=${APP_KEY}; skipping"
  exit 0
fi

load_sentry_auth
if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
  log "SENTRY_AUTH_TOKEN unset; skipping dSYM upload"
  exit 0
fi

if ! command -v sentry-cli >/dev/null 2>&1; then
  log "sentry-cli not on PATH; trying official installer"
  if ! curl -sL https://sentry.io/get-cli/ | SENTRY_CLI_VERSION="" bash >/dev/null 2>&1; then
    log "warning: sentry-cli install failed; continuing without upload"
    exit 0
  fi
  # Official installer: ~/.sentry/bin (current) or ~/.sentry-cli (older).
  export PATH="${HOME}/.sentry/bin:${HOME}/.sentry-cli:${HOME}/.local/bin:${PATH}:/opt/homebrew/bin"
fi
if ! command -v sentry-cli >/dev/null 2>&1; then
  log "warning: sentry-cli still missing; skipping artifact upload"
  exit 0
fi

mkdir -p "$LOG_DIR"
targets=()
if [[ -n "$ARCHIVE_PATH" ]]; then
  if [[ -d "$ARCHIVE_PATH" || -f "$ARCHIVE_PATH" ]]; then
    targets+=("$ARCHIVE_PATH")
  else
    log "archive missing at given path; skipping"
    exit 0
  fi
fi
if [[ -n "$SEARCH_DIR" ]]; then
  if [[ -d "$SEARCH_DIR" ]]; then
    while IFS= read -r -d '' dsym; do
      targets+=("$dsym")
    done < <(find "$SEARCH_DIR" -name '*.dSYM' -print0 2>/dev/null || true)
  else
    log "search dir missing; skipping find"
  fi
fi

if [[ ${#targets[@]} -eq 0 ]]; then
  log "no dSYMs or archive to upload; skipping"
  exit 0
fi

log "uploading ${#targets[@]} path(s) to project=${project} (token length ${#SENTRY_AUTH_TOKEN})"
org="${SENTRY_ORG:-simple-with-us}"
ok=0
for target in "${targets[@]}"; do
  set +e
  SENTRY_ORG="$org" SENTRY_PROJECT="$project" \
    sentry-cli debug-files upload --include-sources "$target" \
    >>"${LOG_DIR}/sentry-debug-files.log" 2>&1
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    ok=$((ok + 1))
  else
    log "warning: debug-files upload rc=${rc} for one path; see ${LOG_DIR}/sentry-debug-files.log"
  fi
done

if [[ $ok -gt 0 ]]; then
  log "debug-files upload ok (${ok}/${#targets[@]})"
else
  log "warning: no path uploaded successfully; see ${LOG_DIR}/sentry-debug-files.log"
fi
exit 0
