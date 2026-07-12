#!/usr/bin/env bash
# Settings override wiring for layouts, workspaces, theme, rofi.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "settings-overrides-layout-theme"
waybar_test_gen_sandbox
if ! waybar_test_gen_default; then
  echo "FAIL: default generate failed before layout/theme overrides" >&2
  exit 1
fi

echo "Testing layout/theme/rofi settings overrides..."
cp "$ROOT_DIR/scripts/ci/lib/fixtures/settings/generator-overrides.jsonc" \
  "$TEST_DIR/data/waybar-settings.jsonc"
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed with custom configuration" >&2
  exit 1
fi
validate_all_generated_files "layout/theme overrides" || fail=1
clean_bar=$(waybar_test_read_jsonc "$TEST_DIR/includes/bar-defaults.generated.jsonc")

# Assert keyboard layout and gamemode configuration overrides compiled correctly
clean_center=$(waybar_test_read_jsonc "$TEST_DIR/modules/center-extras.generated.jsonc")
waybar_test_assert_jq "$clean_center" '."custom/keyboard-layout"."on-click" == "TEST_KEYBOARD_ON_CLICK"' "Custom keyboard on-click override not compiled correctly into center-extras.generated.jsonc"
waybar_test_assert_jq "$clean_center" '."custom/gamemode"."on-click" == "TEST_GAMEMODE_ON_CLICK"' "Custom gamemode on-click override not compiled correctly into center-extras.generated.jsonc"

# Assert layouts.top.modules_left override compiled correctly into top-left.generated.jsonc
clean_top_left=$(waybar_test_read_jsonc "$TEST_DIR/layouts/top-left.generated.jsonc")
waybar_test_assert_jq "$clean_top_left" '."modules-left" == ["group/desk-controls", "group/media"]' "Custom modules-left override not compiled correctly into top-left.generated.jsonc"

# Assert workspaces.slot_count override compiled correctly into groups-desk-hypr.generated.jsonc
clean_desk_hypr=$(waybar_test_read_jsonc "$TEST_DIR/modules/groups-desk-hypr.generated.jsonc")
if ! echo "$clean_desk_hypr" | jq -e '."group/desk-hypr".modules | length == 11' >/dev/null 2>&1; then
  # 8 slots + 3 tail modules ("hyprland/submap", "custom/hyprlight", "custom/hyprwhspr") = 11 modules total
  echo "FAIL: Custom workspaces slot count override not compiled correctly into groups-desk-hypr.generated.jsonc" >&2
  fail=1
fi

# Assert workspaces.generated.jsonc was emitted from slot_count
if [ ! -f "$TEST_DIR/modules/workspaces.generated.jsonc" ]; then
  echo "FAIL: workspaces.generated.jsonc was not generated!" >&2
  fail=1
fi
clean_ws=$(waybar_test_read_jsonc "$TEST_DIR/modules/workspaces.generated.jsonc")
waybar_test_assert_jq "$clean_ws" '."custom/ws-7"' "workspaces.generated.jsonc missing custom/ws-7 for slot_count=8"
if echo "$clean_ws" | jq -e '."custom/ws-8"' >/dev/null 2>&1; then
  echo "FAIL: workspaces.generated.jsonc unexpectedly has custom/ws-8 when slot_count=8" >&2
  fail=1
fi
# Override wins over keyboard-layout-click default
waybar_test_assert_jq "$clean_center" '."custom/keyboard-layout"."on-click" == "TEST_KEYBOARD_ON_CLICK"' "keyboard on-click override should win over keyboard-layout-click default"
# Override fixture can set overlay explicitly
if echo "$clean_bar" | jq -e 'has("layer")' >/dev/null 2>&1; then
  if ! echo "$clean_bar" | jq -e '.layer == "overlay" or .layer == "top" or .layer == "bottom"' >/dev/null 2>&1; then
    echo "FAIL: bar layer has unexpected value" >&2
    fail=1
  fi
fi

# Assert theme configurations CSS tokens generated correctly
css_tokens="$TEST_DIR/theme/tokens.generated.css"
if [ -f "$css_tokens" ]; then
  if ! grep -q "font-family: \"MOCK_FONT_FAMILY\"" "$css_tokens"; then
    echo "FAIL: Overridden font family not found in generated tokens CSS" >&2
    fail=1
  fi
  if ! grep -q "font-size: 44px" "$css_tokens"; then
    # Note: tooltip_font_size 44 styles 'tooltip label'
    echo "FAIL: Overridden tooltip font size not found in generated tokens CSS" >&2
    fail=1
  fi
  if ! grep -q "border-radius: 12px" "$css_tokens"; then
    echo "FAIL: Overridden border radius not found in generated tokens CSS" >&2
    fail=1
  fi
  if ! grep -q "background: rgba(9, 9, 9, 0.99)" "$css_tokens"; then
    echo "FAIL: Overridden background color not found in generated tokens CSS" >&2
    fail=1
  fi
  if ! grep -q "background: #010203" "$css_tokens"; then
    echo "FAIL: theme.colors.tooltip_background not found in generated tokens CSS" >&2
    fail=1
  fi
  if ! grep -q "border: 1px solid #040506" "$css_tokens"; then
    echo "FAIL: theme.colors.tooltip_border not found in generated tokens CSS" >&2
    fail=1
  fi
  if ! grep -q "padding: 9px 11px" "$css_tokens"; then
    echo "FAIL: theme.tooltip_padding not found in generated tokens CSS" >&2
    fail=1
  fi
else
  echo "FAIL: tokens.generated.css was not created!" >&2
  fail=1
fi
# Assert Rofi wifi and switcher settings resolve to overridden values
test_width=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/lib/waybar-settings.sh; waybar_settings_get '.rofi.wifi.width' 'default'")
if [ "$test_width" != "888" ]; then
  echo "FAIL: Rofi wifi width override failed to resolve! Resolved: $test_width" >&2
  fail=1
fi

test_switcher_width=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/lib/waybar-settings.sh; waybar_settings_get '.rofi.switcher.width' 'default'")
if [ "$test_switcher_width" != "999" ]; then
  echo "FAIL: Rofi switcher width override failed to resolve! Resolved: $test_switcher_width" >&2
  fail=1
fi

echo "PASS: settings overrides (layout/theme)"
waybar_test_end
