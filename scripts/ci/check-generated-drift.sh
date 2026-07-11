#!/usr/bin/env bash
# Fail when committed generated artifacts diverge from `make generate`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export WAYBAR_HOME="$ROOT"
export WAYBAR_SCRIPTS="$ROOT/scripts"
# Hermetic generate: host session must not reshape committed desk/clock artifacts.
# kde ⇒ workspace slots only (matches committed groups-desk-hypr); override via WAYBAR_DRIFT_COMPOSITOR.
export WAYBAR_COMPOSITOR="${WAYBAR_DRIFT_COMPOSITOR:-kde}"
# Isolate compositor cache from the live session.
_drift_runtime=""
if [ -n "${WAYBAR_DRIFT_RUNTIME_DIR:-}" ]; then
  export XDG_RUNTIME_DIR="$WAYBAR_DRIFT_RUNTIME_DIR"
else
  _drift_runtime="$(mktemp -d "${TMPDIR:-/tmp}/waybar-drift.XXXXXX")"
  export XDG_RUNTIME_DIR="$_drift_runtime"
  trap 'rm -rf "$_drift_runtime"' EXIT
fi

if ! command -v git >/dev/null 2>&1; then
  echo "FAIL: git is required for generated-drift check" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required for generate" >&2
  exit 1
fi

echo "=== Regenerating from data/ ==="
make generate

paths=(
  data/waybar-settings.json
  includes
  layouts
  modules
  theme
)

echo "=== Checking for drift ==="
if git diff --quiet -- "${paths[@]}"; then
  echo "ok: generated artifacts match make generate"
  exit 0
fi

echo "FAIL: generated artifacts are out of date. Run: make generate" >&2
git --no-pager diff --stat -- "${paths[@]}" >&2 || true
git --no-pager diff -- "${paths[@]}" >&2 || true
exit 1
