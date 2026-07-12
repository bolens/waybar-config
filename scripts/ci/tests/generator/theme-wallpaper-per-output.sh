#!/usr/bin/env bash
# Per-output wallpaper CSS blocks vs global unscoped emit.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "theme-wallpaper-per-output"
waybar_test_gen_sandbox
waybar_test_compile_settings
mv "$TEST_DIR/data/waybar-settings.jsonc" "$TEST_DIR/data/waybar-settings.jsonc.bak"

fixtures="$TEST_DIR/data/wallpaper-fixtures"
mkdir -p "$fixtures"
# Tiny placeholder images (extract uses WAYBAR_TEST_COLORS_MAP, not pixels).
for name in wall-a wall-b wall-c wall-d; do
  printf 'FIXTURE-%s\n' "$name" >"$fixtures/${name}.png"
done

export WAYBAR_TEST_OUTPUTS="DP-1,HDMI-A-1,eDP-1,DP-2"
export WAYBAR_TEST_COLORS_MAP
WAYBAR_TEST_COLORS_MAP=$(jq -cn \
  --arg a "$fixtures/wall-a.png" \
  --arg b "$fixtures/wall-b.png" \
  --arg c "$fixtures/wall-c.png" \
  --arg d "$fixtures/wall-d.png" \
  '{
    ($a): {
      background: "rgba(10, 20, 30, 0.91)",
      foreground: "#aabbcc",
      border: "rgba(11, 22, 33, 0.4)",
      workspace_active: "rgba(100, 10, 10, 0.5)"
    },
    ($b): {
      background: "rgba(40, 50, 60, 0.91)",
      foreground: "#ddeeff",
      border: "rgba(44, 55, 66, 0.4)",
      workspace_active: "rgba(10, 100, 10, 0.5)"
    },
    ($c): {
      background: "rgba(70, 80, 90, 0.91)",
      foreground: "#112233",
      border: "rgba(77, 88, 99, 0.4)",
      workspace_active: "rgba(10, 10, 100, 0.5)"
    },
    ($d): {
      background: "rgba(1, 2, 3, 0.91)",
      foreground: "#445566",
      border: "rgba(4, 5, 6, 0.4)",
      workspace_active: "rgba(200, 100, 50, 0.5)"
    }
  }')

settings_json="$TEST_DIR/data/waybar-settings.json"
tmp=$(mktemp)
jq \
  --arg a "$fixtures/wall-a.png" \
  --arg b "$fixtures/wall-b.png" \
  --arg c "$fixtures/wall-c.png" \
  --arg d "$fixtures/wall-d.png" \
  '
    .theme.mode = "wallpaper"
    | .theme.wallpaper.scope = "per_output"
    | .theme.wallpaper.outputs = {
        "DP-1": $a,
        "HDMI-A-1": $b,
        "eDP-1": $c,
        "DP-2": $d
      }
  ' "$settings_json" >"$tmp"
mv "$tmp" "$settings_json"

wall_css="$TEST_DIR/theme/tokens.wallpaper.generated.css"
WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  bash "$TEST_DIR/scripts/tools/theme-apply-wallpaper.sh"

echo "Asserting distinct per-output CSS blocks..."
if [ ! -f "$wall_css" ]; then
  echo "FAIL: tokens.wallpaper.generated.css was not written" >&2
  fail=1
else
  for cls in DP-1 HDMI-A-1 eDP-1 DP-2; do
    if ! grep -q "window.${cls}#waybar" "$wall_css"; then
      echo "FAIL: missing scoped block window.${cls}#waybar" >&2
      fail=1
    fi
  done
  if ! grep -q 'background: rgba(10, 20, 30, 0.91)' "$wall_css"; then
    echo "FAIL: DP-1 colors missing from wallpaper CSS" >&2
    fail=1
  fi
  if ! grep -q 'background: rgba(40, 50, 60, 0.91)' "$wall_css"; then
    echo "FAIL: HDMI-A-1 colors missing from wallpaper CSS" >&2
    fail=1
  fi
  if ! grep -q 'background: rgba(70, 80, 90, 0.91)' "$wall_css"; then
    echo "FAIL: eDP-1 colors missing from wallpaper CSS" >&2
    fail=1
  fi
  if ! grep -q 'background: rgba(1, 2, 3, 0.91)' "$wall_css"; then
    echo "FAIL: DP-2 colors missing from wallpaper CSS" >&2
    fail=1
  fi
  if ! grep -q 'window.DP-1#waybar #custom-ws-0.ws-active' "$wall_css"; then
    echo "FAIL: missing workspace active pill selectors under window.DP-1" >&2
    fail=1
  fi
fi

echo "Asserting global scope emits unscoped overrides..."
tmp=$(mktemp)
jq '.theme.wallpaper.scope = "global"' "$settings_json" >"$tmp"
mv "$tmp" "$settings_json"
WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  bash "$TEST_DIR/scripts/tools/theme-apply-wallpaper.sh"

if [ ! -f "$wall_css" ]; then
  echo "FAIL: global apply did not write wallpaper CSS" >&2
  fail=1
else
  if ! grep -qE '^window#waybar \{' "$wall_css"; then
    echo "FAIL: global scope should emit unscoped window#waybar block" >&2
    fail=1
  fi
  if grep -qE 'window\.(DP-1|HDMI-A-1|eDP-1|DP-2)#waybar' "$wall_css"; then
    echo "FAIL: global scope should not emit per-output window.OUT blocks" >&2
    fail=1
  fi
fi

echo "Asserting missing wallpaper falls back to theme.colors..."
tmp=$(mktemp)
jq '
  .theme.wallpaper.scope = "per_output"
  | .theme.wallpaper.outputs = {}
  | .theme.wallpaper.image = null
' "$settings_json" >"$tmp"
mv "$tmp" "$settings_json"
unset WAYBAR_TEST_COLORS_MAP || true
WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  bash "$TEST_DIR/scripts/tools/theme-apply-wallpaper.sh"
if [ ! -f "$wall_css" ]; then
  echo "FAIL: fallback apply did not write wallpaper CSS" >&2
  fail=1
elif ! grep -q 'window.DP-1#waybar' "$wall_css"; then
  echo "FAIL: fallback should still emit per-output blocks from theme.colors" >&2
  fail=1
fi

echo "PASS: theme-wallpaper-per-output checks"
waybar_test_end
