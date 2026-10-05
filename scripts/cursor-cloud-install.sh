#!/usr/bin/env bash
# Cursor cloud agent install for ContactLogo.  Idempotent, non-interactive,
# Linux (Ubuntu) only.  Runs during the Cursor Build step.
#
# macOS / iOS / Xcode / Swift steps are skipped — ContactLogo's native shells
# (ContactLogoiOS, ContactLogoMac, ContactLogoKit) build on macOS only.  This
# Linux cloud VM has no Xcode toolchain; a one-line note is printed instead.
#
# Never echoes, prints, or logs secret values.  Names only.
set -euo pipefail

cd "$(dirname "$0")/.."

REPO_ROOT="$(pwd)"
STATE_DIR="${HOME}/.cursor-cloud-env"
mkdir -p "${STATE_DIR}"
chmod 0700 "${STATE_DIR}"

echo "==> Cursor cloud install: ContactLogo (Linux / Ubuntu)"

# --- 1. Toolchain probe -----------------------------------------------------
NODE_BIN="$(command -v node || true)"
NPM_BIN="$(command -v npm || true)"
if [[ -z "${NODE_BIN}" || -z "${NPM_BIN}" ]]; then
  echo "==> Node.js / npm not found; relying on the composer-latest image."
else
  echo "==> Node: $(node --version)  npm: $(npm --version)"
fi

# --- 2. web/ deps (primary app surface) ------------------------------------
if [[ -f "web/package-lock.json" ]]; then
  echo "==> npm ci --prefix web (production + dev deps for tests / typecheck)"
  # --include=dev is the default for `npm ci` outside of production envs;
  # pass it explicitly to be safe in non-TTY sandboxes.
  npm ci --include=dev --prefix web
else
  echo "==> web/package-lock.json missing; falling back to npm install --prefix web"
  npm install --include=dev --prefix web
fi

# --- 3. Root deps (root package.json has no deps today, but keep parity) ---
if [[ -f "package.json" && ! -f "package-lock.json" ]]; then
  echo "==> No root package-lock.json; skipping root install (web/ is canonical)."
fi

# --- 4. Infisical CLI (best-effort) ----------------------------------------
# The web app already ships scripts/sync-infisical-env.ts which calls the
# official Infisical REST API via Node fetch — no CLI required.  Try the
# official Linux install once; if it fails, the start script will use the
# Node helper instead.  Never print secret values.
if ! command -v infisical >/dev/null 2>&1; then
  echo "==> Installing Infisical CLI (official Linux installer)"
  if curl -fsSL --max-time 30 https://infisical.com/api/cli >/tmp/infisical-install.sh 2>/dev/null; then
    bash /tmp/infisical-install.sh >/dev/null 2>&1 || true
    rm -f /tmp/infisical-install.sh
  fi
  if command -v infisical >/dev/null 2>&1; then
    echo "==> Infisical CLI installed: $(infisical --version 2>/dev/null || echo 'unknown version')"
  else
    echo "==> Infisical CLI unavailable; start script will use web/scripts/sync-infisical-env.ts via the Infisical REST API."
  fi
else
  echo "==> Infisical CLI already present: $(infisical --version 2>/dev/null || echo 'unknown version')"
fi

# --- 5. macOS / iOS / Swift note -------------------------------------------
echo "==> macOS / iOS / Swift / Xcode steps SKIPPED — those shells build on Mac only.  Linux VM has no Xcode toolchain."

echo "==> Cursor cloud install: complete."
echo "    Web dev:    npm run dev"
echo "    Typecheck:  npm run typecheck"
echo "    Test:       npm test   (web only on Linux)"
