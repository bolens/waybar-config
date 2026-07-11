#!/usr/bin/env bash
# Diff shell sources against shfmt (2-space, bash).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SHFMT_VERSION="${SHFMT_VERSION:-3.13.1}"
FLAGS=(-ln bash -i 2 -ci -bn)

resolve_shfmt() {
  if [ -n "${SHFMT_BIN:-}" ] && [ -x "$SHFMT_BIN" ]; then
    printf '%s\n' "$SHFMT_BIN"
    return 0
  fi
  if command -v shfmt >/dev/null 2>&1; then
    command -v shfmt
    return 0
  fi
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-ci"
  local bin="$cache/shfmt-${SHFMT_VERSION}"
  if [ -x "$bin" ]; then
    printf '%s\n' "$bin"
    return 0
  fi
  mkdir -p "$cache"
  local url="https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_amd64"
  echo "Downloading shfmt v${SHFMT_VERSION}..." >&2
  curl -fsSL -o "$bin" "$url"
  chmod +x "$bin"
  printf '%s\n' "$bin"
}

SHFMT="$(resolve_shfmt)"
echo "=== shfmt $($SHFMT --version) ${FLAGS[*]} ==="

if [ "${1:-}" = "--write" ] || [ "${1:-}" = "-w" ]; then
  "$SHFMT" -w "${FLAGS[@]}" "$ROOT/scripts"
  echo "ok: reformatted scripts/"
  exit 0
fi

if ! "$SHFMT" -d "${FLAGS[@]}" "$ROOT/scripts"; then
  echo "FAIL: shfmt drift. Run: make fmt-shell" >&2
  exit 1
fi
echo "ok: scripts match shfmt"
