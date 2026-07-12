#!/usr/bin/env bash
# Slot-count CSS SoT: workspaces/dock_windows.slot_count ↔ generated layout + semantic.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "slot-css-contracts"
waybar_test_gen_sandbox
if ! waybar_test_gen_default; then
  echo "FAIL: default generate failed" >&2
  exit 1
fi

. "$TEST_DIR/scripts/lib/css-selectors-lib.sh"

fail=0
settings="$TEST_DIR/data/waybar-settings.json"
ws_css="$TEST_DIR/theme/workspaces.generated.css"
dock_css="$TEST_DIR/theme/dock-windows.generated.css"
semantic="$TEST_DIR/theme/semantic-colors.generated.css"

assert_range_present_absent() {
  local label="$1"
  local file="$2"
  local prefix="$3"
  local count="$4"
  local i
  for ((i = 0; i < count; i++)); do
    if ! grep -Fq "${prefix}${i}" "$file"; then
      echo "FAIL: $label missing ${prefix}${i} in $(basename "$file") (count=$count)" >&2
      fail=1
    fi
  done
  if grep -Fq "${prefix}${count}" "$file"; then
    echo "FAIL: $label unexpectedly has ${prefix}${count} in $(basename "$file") (count=$count)" >&2
    fail=1
  fi
}

ws_count="$(waybar_css_slot_count "$settings" workspaces 5 1 10)"
dock_count="$(waybar_css_slot_count "$settings" dock_windows 12 1 16)"

echo "Testing default slot CSS bounds (ws=$ws_count dock=$dock_count)..."
assert_range_present_absent "workspaces" "$ws_css" "#custom-ws-" "$ws_count"
assert_range_present_absent "workspaces" "$semantic" "#custom-ws-" "$ws_count"
assert_range_present_absent "dock-windows" "$dock_css" "#custom-dock-win-" "$dock_count"
assert_range_present_absent "dock-windows" "$semantic" "#custom-dock-win-" "$dock_count"

echo "Testing theme.css imports slot layout CSS..."
if ! grep -Fq 'theme/workspaces.generated.css' "$ROOT_DIR/theme.css"; then
  echo "FAIL: theme.css missing workspaces.generated.css import" >&2
  fail=1
fi
if ! grep -Fq 'theme/dock-windows.generated.css' "$ROOT_DIR/theme.css"; then
  echo "FAIL: theme.css missing dock-windows.generated.css import" >&2
  fail=1
fi

echo "Testing slot_count override regenerates CSS bounds..."
jq '.workspaces.slot_count = 7 | .dock_windows.slot_count = 4' "$settings" >"$settings.tmp"
mv "$settings.tmp" "$settings"
cp "$settings" "$TEST_DIR/data/waybar-settings.jsonc"
bash "$TEST_DIR/scripts/generate/generate-theme-tokens.sh"
bash "$TEST_DIR/scripts/generate/generate-workspaces-css.sh"
bash "$TEST_DIR/scripts/generate/generate-dock-windows-css.sh"

assert_range_present_absent "workspaces-override" "$ws_css" "#custom-ws-" 7
assert_range_present_absent "workspaces-override" "$semantic" "#custom-ws-" 7
assert_range_present_absent "dock-override" "$dock_css" "#custom-dock-win-" 4
assert_range_present_absent "dock-override" "$semantic" "#custom-dock-win-" 4

echo "Testing clamp helpers..."
if [ "$(waybar_css_clamp_int 0 5 1 10)" != "1" ]; then
  echo "FAIL: waybar_css_clamp_int should raise below-min to min" >&2
  fail=1
fi
if [ "$(waybar_css_clamp_int 99 5 1 10)" != "10" ]; then
  echo "FAIL: waybar_css_clamp_int should lower above-max to max" >&2
  fail=1
fi
id_n=$(waybar_css_id_range '#x-' 3 '.y' | grep -c '#x-')
if [ "$id_n" -ne 3 ]; then
  echo "FAIL: waybar_css_id_range 3 emitted $id_n selectors" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "PASS: slot-css-contracts"
waybar_test_end
