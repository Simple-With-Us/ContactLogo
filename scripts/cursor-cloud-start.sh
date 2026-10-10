#!/usr/bin/env bash
# Cursor cloud agent start for ContactLogo.  Runs each agent boot.
#
# - If INFISICAL_CLIENT_ID and INFISICAL_CLIENT_SECRET are set in the Cursor
#   dashboard, log in to Infisical and export the ContactLogo project's
#   secrets for INFISICAL_ENV into:
#       ${HOME}/.cursor-cloud-env/ContactLogo.env         (mode 0600)
#       ${HOME}/.cursor-cloud-env/ContactLogo.source.sh   (set -a; source ...; set +a)
# - If credentials are missing, print the missing dashboard secret NAMES
#   and exit 0 — never fail the agent boot.
# - Never print secret values.  Names only.
set -euo pipefail

cd "$(dirname "$0")/.."

STATE_DIR="${HOME}/.cursor-cloud-env"
REPO_NAME="ContactLogo"
ENV_FILE="${STATE_DIR}/${REPO_NAME}.env"
SOURCE_FILE="${STATE_DIR}/${REPO_NAME}.source.sh"
INFISICAL_ENV_FILE=".cursor/infisical.env"

mkdir -p "${STATE_DIR}"
chmod 0700 "${STATE_DIR}"

# Load committed, non-secret Infisical coordinates.
# shellcheck disable=SC1090
if [[ -f "${INFISICAL_ENV_FILE}" ]]; then
  set -a
  # Filter out any commented lines so we never accidentally export them.
  # shellcheck disable=SC1090
  source <(grep -v '^[[:space:]]*#' "${INFISICAL_ENV_FILE}" | grep -v '^[[:space:]]*$')
  set +a
fi

# --- 1. Missing-credentials early-exit -------------------------------------
if [[ -z "${INFISICAL_CLIENT_ID:-}" || -z "${INFISICAL_CLIENT_SECRET:-}" ]]; then
  echo "[cursor-cloud-start] Infisical credentials not set; skipping secret load."
  echo "[cursor-cloud-start] Add these NAMES to the Cursor dashboard for ContactLogo:"
  echo "  - INFISICAL_CLIENT_ID"
  echo "  - INFISICAL_CLIENT_SECRET"
  exit 0
fi

# Owner directive 2026-10-10: Infisical prod is the only environment (dev and
# staging are being retired).  Default to it and refuse anything else.
INFISICAL_ENV="${INFISICAL_ENV:-prod}"
if [[ "${INFISICAL_ENV}" != "prod" ]]; then
  echo "[cursor-cloud-start] INFISICAL_ENV must be prod (dev and staging are retired); refusing to load." >&2
  exit 1
fi

if [[ -z "${INFISICAL_PROJECT_ID:-}" || -z "${INFISICAL_ENV:-}" ]]; then
  echo "[cursor-cloud-start] Infisical project coordinates missing in ${INFISICAL_ENV_FILE}; skipping secret load."
  echo "[cursor-cloud-start] Required: INFISICAL_PROJECT_ID, INFISICAL_ENV (and optionally INFISICAL_DOMAIN)."
  exit 0
fi

echo "[cursor-cloud-start] Loading Infisical secrets for project ${INFISICAL_PROJECT_ID} (env: ${INFISICAL_ENV}) into ${ENV_FILE}"

# --- 2. Pull secrets --------------------------------------------------------
# Prefer the web app's existing Node helper (scripts/sync-infisical-env.ts)
# which already handles auth, env selection, and quoting.  It writes
# .env.local under web/ — we use a temp .env.local and reformat it into the
# canonical 0600 env file under ~/.cursor-cloud-env.  The temp file is
# removed at the end.
TMP_LOCAL="$(mktemp -t contactlogo-env-XXXXXX.local)"
TMP_LOCAL_DIR="$(mktemp -d -t contactlogo-sync-XXXXXX)"
chmod 0700 "${TMP_LOCAL_DIR}"
cleanup() {
  rm -f "${TMP_LOCAL}" || true
  rm -rf "${TMP_LOCAL_DIR}" || true
}
trap cleanup EXIT

# The web helper writes to web/.env.local by default; redirect to our temp
# dir by passing an env override.  We re-implement minimal fetch in a
# portable shell+curl+python3 fallback so the start script does not depend
# on the web helper being able to import TypeScript at agent boot time.
PULL_OK=0
if command -v infisical >/dev/null 2>&1; then
  echo "[cursor-cloud-start] Using infisical CLI"
  if infisical export \
      --projectId "${INFISICAL_PROJECT_ID}" \
      --env "${INFISICAL_ENV}" \
      --domain "${INFISICAL_DOMAIN:-https://app.infisical.com}" \
      --format dotenv \
      --plain 2>/tmp/infisical-export.err >"${TMP_LOCAL}"; then
    PULL_OK=1
  else
    echo "[cursor-cloud-start] infisical CLI export failed; falling back to REST fetch."
  fi
fi

if [[ "${PULL_OK}" -eq 0 ]]; then
  # REST fallback via curl + python3 — never prints values.
  echo "[cursor-cloud-start] Using REST fallback (curl + python3)"
  DOMAIN="${INFISICAL_DOMAIN:-https://app.infisical.com}"
  # Step A: machine-identity login → access token (sent in body, never logged).
  LOGIN_BODY="$(printf '{"clientId":"%s","clientSecret":"%s"}' \
      "${INFISICAL_CLIENT_ID}" "${INFISICAL_CLIENT_SECRET}")"
  LOGIN_RESPONSE="$(curl -fsS --max-time 30 \
      -H 'Content-Type: application/json' \
      -d "${LOGIN_BODY}" \
      "${DOMAIN}/api/v1/auth/universal-auth/login" 2>/tmp/infisical-login.err || true)"
  if [[ -z "${LOGIN_RESPONSE}" ]]; then
    echo "[cursor-cloud-start] Infisical login failed; aborting secret load (no values printed)."
    cat /tmp/infisical-login.err >/dev/null 2>&1 || true
    exit 0
  fi

  ACCESS_TOKEN="$(printf '%s' "${LOGIN_RESPONSE}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("accessToken",""))' 2>/dev/null || true)"
  if [[ -z "${ACCESS_TOKEN}" ]]; then
    echo "[cursor-cloud-start] Infisical login response did not include accessToken; aborting."
    exit 0
  fi

  # Step B: list secrets for the env (paginated by name ascending).
  SECRETS_JSON="$(curl -fsS --max-time 30 \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H 'Content-Type: application/json' \
      "${DOMAIN}/api/v3/secrets/raw?projectId=${INFISICAL_PROJECT_ID}&environmentSlug=${INFISICAL_ENV}&workspaceId=${INFISICAL_PROJECT_ID}&includeImports=false&recursive=false" 2>/tmp/infisical-list.err || true)"
  if [[ -z "${SECRETS_JSON}" ]]; then
    echo "[cursor-cloud-start] Infisical list-secrets failed; aborting."
    exit 0
  fi

  # Step C: serialize to dotenv into the temp file.  python3 never prints values.
  python3 - "${SECRETS_JSON}" "${TMP_LOCAL}" <<'PY'
import json, sys, re
try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
items = data.get("secrets") or data.get("items") or []
def quote(v: str) -> str:
    if v is None:
        return '""'
    if re.search(r'[\s#"\']', v):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return v
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    for it in items:
        key = it.get("key")
        val = it.get("value")
        if not key:
            continue
        fh.write(f"{key}={quote(val or '')}\n")
PY
  PULL_OK=1
fi

# --- 3. Move temp → canonical env file (0600) ------------------------------
if [[ "${PULL_OK}" -eq 1 && -s "${TMP_LOCAL}" ]]; then
  install -m 0600 "${TMP_LOCAL}" "${ENV_FILE}"
  cat >"${SOURCE_FILE}" <<EOF
# Auto-generated by scripts/cursor-cloud-start.sh — do not edit by hand.
# Source this file to load ContactLogo Infisical secrets into the current shell.
#   set -a; source "${ENV_FILE}"; set +a
EOF
  chmod 0600 "${SOURCE_FILE}"
  KEY_COUNT="$(grep -cE '^[A-Za-z_][A-Za-z0-9_]*=' "${ENV_FILE}" 2>/dev/null || true)"
  echo "[cursor-cloud-start] Wrote ${KEY_COUNT} secret(s) to ${ENV_FILE} (mode 0600)."
  echo "[cursor-cloud-start] Source with: set -a; source ${ENV_FILE}; set +a"
else
  echo "[cursor-cloud-start] No secrets written (empty result or pull failed)."
fi

exit 0
