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

# dock-appicons / dock-windows bake absolute file://$WAYBAR_HOME/theme/… URLs so
# GTK hot style reload keeps background-image. That makes a cross-host false
# positive here (runner vs developer $HOME). Compare with those prefixes collapsed.
_norm_css_urls() {
  # shellcheck disable=SC2016
  sed -E 's|url\("file://[^"]+/theme/|url("file://__WAYBAR_HOME__/theme/|g'
}

_portable_theme_only=1
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    theme/*.generated.css) ;;
    *)
      _portable_theme_only=0
      break
      ;;
  esac
done < <(git diff --name-only -- "${paths[@]}")

if [ "$_portable_theme_only" -eq 1 ]; then
  drift=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! diff -q \
      <(git show "HEAD:$f" | _norm_css_urls) \
      <(_norm_css_urls <"$f") >/dev/null 2>&1; then
      drift=1
      break
    fi
  done < <(git diff --name-only -- "${paths[@]}")
  if [ "$drift" -eq 0 ]; then
    echo "ok: generated artifacts match make generate (ignoring host file:// theme URLs)"
    exit 0
  fi
fi

echo "FAIL: generated artifacts are out of date. Run: make generate" >&2
git --no-pager diff --stat -- "${paths[@]}" >&2 || true
git --no-pager diff -- "${paths[@]}" >&2 || true
exit 1
