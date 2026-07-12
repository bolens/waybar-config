#!/usr/bin/env bash
# Assert generators wire $WAYBAR_OUTPUT_NAME when per_output toggles are on.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "per-output-modules"
waybar_test_gen_sandbox
if ! waybar_test_gen_default; then
  echo "FAIL: default generate failed before per-output-modules" >&2
  exit 1
fi

# Ensure toggles are on (SoT defaults already true; force for clarity).
waybar_test_patch_settings_py <<'PY'
data.setdefault("active_window", {})["per_output"] = True
data.setdefault("brightness", {})["per_output"] = True
data.setdefault("capture", {})["per_output"] = True
data.setdefault("window_switcher", {})["per_output"] = True
data.setdefault("dock_windows", {})["per_output"] = True
PY
"$TEST_DIR/scripts/generate/generate-active-window-modules.sh"
"$TEST_DIR/scripts/generate/generate-utilities-modules.sh"
"$TEST_DIR/scripts/generate/generate-dock-windows-modules.sh" 2>/dev/null || true

aw_json=$(waybar_test_read_jsonc "$TEST_DIR/modules/compositor.generated.jsonc")
util_json=$(waybar_test_read_jsonc "$TEST_DIR/modules/utilities.generated.jsonc")

assert_field_has_output() {
  local json="$1"
  local path="$2"
  local label="$3"
  local val
  val=$(printf '%s' "$json" | jq -r "$path // empty")
  if [ -z "$val" ]; then
    echo "FAIL: $label — missing field $path" >&2
    fail=1
    return 0
  fi
  case "$val" in
    *'$WAYBAR_OUTPUT_NAME'*)
      echo "PASS: $label"
      ;;
    *)
      echo "FAIL: $label — expected \$WAYBAR_OUTPUT_NAME in: $val" >&2
      fail=1
      ;;
  esac
}

assert_field_has_output "$aw_json" '."custom/active-window".exec' "active-window exec"
assert_field_has_output "$aw_json" '."custom/active-window"."on-click"' "active-window on-click → switcher"
assert_field_has_output "$util_json" '."custom/brightness".exec' "brightness exec"
assert_field_has_output "$util_json" '."custom/brightness"."on-click"' "brightness on-click"
assert_field_has_output "$util_json" '."custom/brightness"."on-scroll-up"' "brightness scroll-up"
assert_field_has_output "$util_json" '."custom/screenshot"."on-click"' "screenshot on-click"
assert_field_has_output "$util_json" '."custom/screenshot"."on-click-right"' "screenshot full"
assert_field_has_output "$util_json" '."custom/screenrecord"."on-click"' "screenrecord on-click"

dock="$TEST_DIR/modules/dock-windows.generated.jsonc"
if [ -f "$dock" ]; then
  dock_json=$(waybar_test_read_jsonc "$dock")
  dock_exec=$(printf '%s' "$dock_json" | jq -r '."custom/dock-win-0".exec // empty')
  if [ -n "$dock_exec" ]; then
    case "$dock_exec" in
      *'$WAYBAR_OUTPUT_NAME'*) echo "PASS: dock-win slot output wiring present" ;;
      *)
        echo "FAIL: dock-win-0 lacks \$WAYBAR_OUTPUT_NAME: $dock_exec" >&2
        fail=1
        ;;
    esac
  else
    echo "FAIL: custom/dock-win-0 missing from dock-windows.generated.jsonc" >&2
    fail=1
  fi
fi

# Off toggle: per_output false → no output arg
waybar_test_patch_settings_py <<'PY'
data["active_window"]["per_output"] = False
data["brightness"]["per_output"] = False
data["capture"]["per_output"] = False
PY
"$TEST_DIR/scripts/generate/generate-active-window-modules.sh"
"$TEST_DIR/scripts/generate/generate-utilities-modules.sh"

aw_off=$(waybar_test_read_jsonc "$TEST_DIR/modules/compositor.generated.jsonc")
util_off=$(waybar_test_read_jsonc "$TEST_DIR/modules/utilities.generated.jsonc")

assert_field_lacks_output() {
  local json="$1"
  local path="$2"
  local label="$3"
  local val
  val=$(printf '%s' "$json" | jq -r "$path // empty")
  case "$val" in
    *'$WAYBAR_OUTPUT_NAME'*)
      echo "FAIL: $label — still has \$WAYBAR_OUTPUT_NAME: $val" >&2
      fail=1
      ;;
    *)
      echo "PASS: $label"
      ;;
  esac
}

assert_field_lacks_output "$aw_off" '."custom/active-window".exec' "active-window omits output when per_output=false"
assert_field_lacks_output "$util_off" '."custom/brightness".exec' "brightness omits output when per_output=false"
assert_field_lacks_output "$util_off" '."custom/screenshot"."on-click"' "screenshot omits output when per_output=false"

echo "Testing hypr_tools.submap_per_output CSS generator..."
submap_css="$TEST_DIR/theme/submap-per-output.generated.css"
"$TEST_DIR/scripts/generate/generate-submap-css.sh"
if [ ! -f "$submap_css" ]; then
  echo "FAIL: submap-per-output.generated.css missing after generate" >&2
  fail=1
elif ! grep -q 'submap_per_output is off' "$submap_css"; then
  echo "FAIL: expected stub CSS when submap_per_output is off" >&2
  fail=1
else
  echo "PASS: submap_per_output off → stub CSS"
fi

waybar_test_patch_settings_py <<'PY'
data.setdefault("hypr_tools", {})["submap_per_output"] = True
PY
"$TEST_DIR/scripts/generate/generate-submap-css.sh"
if ! grep -qE 'window\.[A-Za-z0-9_-]+ #submap' "$submap_css"; then
  echo "FAIL: enabled submap_per_output should emit window.<OUTPUT> #submap selectors" >&2
  fail=1
elif grep -q 'submap_per_output is off' "$submap_css"; then
  echo "FAIL: enabled submap_per_output still emits stub" >&2
  fail=1
else
  echo "PASS: submap_per_output on → per-output #submap CSS"
fi

waybar_test_end
