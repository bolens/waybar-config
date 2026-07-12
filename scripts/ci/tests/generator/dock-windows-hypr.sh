#!/usr/bin/env bash
# dock_windows.enabled layout injection + Hyprland submap overlay.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "dock-windows-hypr"
waybar_test_gen_sandbox

echo "Testing dock_windows toggle and hyprland/submap overlay..."

# Default: dock-windows on bottom center (enabled=true)
if ! waybar_test_gen_modules; then
  echo "FAIL: default generate failed" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/layouts/bottom.generated.jsonc" \
  '."modules-center" | index("group/dock-windows")' \
  "dock_windows.enabled=true should append group/dock-windows to bottom center by default"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/dock-windows.generated.jsonc" \
  'has("custom/dock-win-0")' \
  "dock-win-0 slot module should be generated"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/dock-windows.generated.jsonc" \
  '."custom/dock-win-0".exec | test("WAYBAR_OUTPUT_NAME")' \
  "dock-win slot exec should pass WAYBAR_OUTPUT_NAME"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups-dock-windows.generated.jsonc" \
  '."group/dock-windows".modules | length > 0' \
  "group/dock-windows should list slots"

# Disable path
waybar_test_compile_settings
jq '.dock_windows.enabled = false' "$TEST_DIR/data/waybar-settings.json" >"$TEST_DIR/data/waybar-settings.json.tmp"
mv -f "$TEST_DIR/data/waybar-settings.json.tmp" "$TEST_DIR/data/waybar-settings.json"
cp -f "$TEST_DIR/data/waybar-settings.json" "$TEST_DIR/data/waybar-settings.jsonc"
if ! waybar_test_gen_modules; then
  echo "FAIL: generate with dock_windows.enabled=false failed" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/layouts/bottom.generated.jsonc" \
  '(."modules-center" | index("group/dock-windows")) == null and (."modules-center" | index("custom/dock-windows")) == null' \
  "dock_windows.enabled=false should omit dock-windows group from bottom center"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/dock-windows.generated.jsonc" \
  'has("custom/dock-win-0")' \
  "dock slot defs should still be generated when disabled"
waybar_test_assert_json_file_jq "$TEST_DIR/layouts/bottom.generated.jsonc" \
  '."modules-center" | index("custom/active-window")' \
  "active-window should remain when disabling dock_windows"

# Re-enable for remaining checks
jq '.dock_windows.enabled = true' "$TEST_DIR/data/waybar-settings.json" >"$TEST_DIR/data/waybar-settings.json.tmp"
mv -f "$TEST_DIR/data/waybar-settings.json.tmp" "$TEST_DIR/data/waybar-settings.json"
cp -f "$TEST_DIR/data/waybar-settings.json" "$TEST_DIR/data/waybar-settings.jsonc"

# Preserve real hyprland.jsonc (sandbox normally stubs it to {})
cp "$ROOT_DIR/modules/hyprland.jsonc" "$TEST_DIR/modules/hyprland.jsonc"
WAYBAR_COMPOSITOR=hyprland waybar_test_gen_modules >/dev/null || {
  echo "FAIL: hyprland generate failed" >&2
  fail=1
}
# JSONC may contain comments — strip before jq
clean_native=$(waybar_test_read_jsonc "$TEST_DIR/modules/hyprland.native.generated.jsonc")
waybar_test_assert_jq "$clean_native" \
  'has("hyprland/submap")' \
  "hyprland.native should include hyprland/submap when compositor=hyprland"
waybar_test_assert_jq "$clean_native" \
  '."hyprland/submap" | has("format") and has("tooltip-format")' \
  "hyprland/submap module must define format + tooltip-format"

desk=$(waybar_test_read_jsonc "$TEST_DIR/modules/groups-desk-hypr.generated.jsonc")
waybar_test_assert_jq "$desk" \
  '."group/desk-hypr".modules | index("hyprland/submap")' \
  "desk-hypr should list hyprland/submap under Hyprland"

# KDE path should not copy native overlay
WAYBAR_COMPOSITOR=kde waybar_test_gen_modules >/dev/null || true
kde_native=$(waybar_test_read_jsonc "$TEST_DIR/modules/hyprland.native.generated.jsonc")
waybar_test_assert_jq "$kde_native" \
  '. == {}' \
  "kde compositor should emit empty hyprland.native.generated.jsonc"

waybar_test_end
