#!/usr/bin/env bash
# Scan the git history / working tree for leaked secrets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GITLEAKS_VERSION="${GITLEAKS_VERSION:-8.30.1}"
cd "$ROOT"

resolve_gitleaks() {
  if [ -n "${GITLEAKS_BIN:-}" ] && [ -x "$GITLEAKS_BIN" ]; then
    printf '%s\n' "$GITLEAKS_BIN"
    return 0
  fi
  if command -v gitleaks >/dev/null 2>&1; then
    command -v gitleaks
    return 0
  fi
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-ci"
  local bin="$cache/gitleaks-${GITLEAKS_VERSION}"
  if [ -x "$bin" ]; then
    printf '%s\n' "$bin"
    return 0
  fi
  mkdir -p "$cache"
  local archive="$cache/gitleaks-${GITLEAKS_VERSION}.tar.gz"
  local url="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
  echo "Downloading gitleaks v${GITLEAKS_VERSION}..." >&2
  curl -fsSL -o "$archive" "$url"
  tar -xzf "$archive" -C "$cache" gitleaks
  mv "$cache/gitleaks" "$bin"
  chmod +x "$bin"
  printf '%s\n' "$bin"
}

GITLEAKS="$(resolve_gitleaks)"
echo "=== gitleaks ==="
# Prefer git-aware scan so gitignored local secrets stay out of CI.
"$GITLEAKS" detect --source "$ROOT" --config "$ROOT/.gitleaks.toml" --verbose --redact
echo "ok: no leaks"
