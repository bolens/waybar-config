#!/usr/bin/env bash
# Guard GTK3 / Waybar CSS compatibility.
# Waybar's CSS parser rejects several modern CSS features and exits on parse errors
# (see journal: 'font-variant-ligatures' / multi-percentage @keyframes).
#
# Usage: check-gtk-css.sh [ROOT]
# ROOT defaults to WAYBAR_HOME or the repo root containing this script.
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Prefer explicit ROOT arg. Do not default to WAYBAR_HOME — generator tests set that
# to a sandbox and would skip scanning the real tree.
ROOT="${1:-$SCRIPT_ROOT}"
cd "$ROOT"

fail=0
# Include generated theme CSS — stylelint deliberately ignores *.generated.css.
# Prune theme/rofi (rofi themes are not loaded by Waybar's GtkCssProvider).
mapfile -t css_files < <(
  find . \( -path ./node_modules -o -path ./.git -o -path './theme/rofi' \) -prune -o \
    -type f -name '*.css' -print \
    | sed 's|^\./||' \
    | sort
)

if [ "${#css_files[@]}" -eq 0 ]; then
  echo "FAIL: no CSS files found under $ROOT" >&2
  exit 1
fi

echo "=== gtk/waybar CSS compat (${#css_files[@]} files under $ROOT) ==="

# Properties GtkCssProvider rejects as invalid names (Waybar exits on parse error).
# Allowlist source: https://docs.gtk.org/gtk3/css-properties.html
# Prefer banning common web/ricing copy-paste props over maintaining a full denylist.
disallowed_props=(
  # Font / effects (seen in this repo + common rice snippets)
  'font-variant-ligatures'
  'font-variant-numeric'
  'font-feature-settings'
  'backdrop-filter'
  'filter'
  'transform'
  # Sizing / overflow (GTK has min-width/min-height only — not width/height/max-*)
  'width'
  'height'
  'max-width'
  'max-height'
  'overflow'
  'overflow-x'
  'overflow-y'
  'text-overflow'
  # Layout (no flexbox/grid/positioning model in GTK CSS)
  'display'
  'flex'
  'gap'
  'position'
  'z-index'
  # Text box
  'line-height'
  'white-space'
  'text-align'
  # Misc browser-only
  'box-sizing'
  'cursor'
)

for prop in "${disallowed_props[@]}"; do
  # Match property declarations (optionally indented), not bare mentions in comments.
  # Use grep (not rg): generator CI images only install jq+dash.
  matches=$(grep -nE "^[[:space:]]*${prop}[[:space:]]*:" "${css_files[@]}" 2>/dev/null || true)
  if [ -n "$matches" ]; then
    echo "FAIL: GTK3/Waybar-unsafe CSS property '${prop}':" >&2
    printf '%s\n' "$matches" >&2
    fail=1
  fi
done

# Multi-percentage keyframe selectors (e.g. "0%, 100% {") crash Waybar's CSS parser.
# Allowed: from { }, to { }, or a single percentage like "50% {".
matches=$(grep -nE \
  -e '^[[:space:]]*[0-9]+%[[:space:]]*,[[:space:]]*[0-9]+%' \
  -e '^[[:space:]]*from[[:space:]]*,[[:space:]]*to' \
  -e '^[[:space:]]*to[[:space:]]*,[[:space:]]*from' \
  "${css_files[@]}" 2>/dev/null || true)
if [ -n "$matches" ]; then
  echo "FAIL: multi-selector @keyframes (use from/to + animation-direction: alternate):" >&2
  printf '%s\n' "$matches" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "gtk-css-compat: FAILED (Waybar will refuse to start on parse errors)" >&2
  exit 1
fi

echo "ok: gtk/waybar CSS compat clean"
