#!/usr/bin/env bash
# Drawer tooltips, intervals, SoT contracts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "drawer-sot-contracts"
waybar_test_gen_sandbox
if ! waybar_test_gen_default; then
  echo "FAIL: default generate failed" >&2
  exit 1
fi
echo "Generator scripts completed successfully."

echo "Testing drawer tooltips, intervals helper, and SoT contracts..."

# Anti-regression: drawer handles must stay static with tooltip-format.
# Waybar's "tooltip" key is a bool — string values are ignored (glyph fallback).
# JSON exec on drawers previously made tooltips disappear entirely.
clean_drawers=$(waybar_test_read_jsonc "$TEST_DIR/modules/drawers.generated.jsonc")
drawer_keys=$(echo "$clean_drawers" | jq -r 'keys[] | select(endswith("-drawer"))')
if [ -z "$drawer_keys" ]; then
  echo "FAIL: no custom/*-drawer modules found in drawers.generated.jsonc" >&2
  fail=1
fi
drawer_count=0
while IFS= read -r drawer_key; do
  [ -z "$drawer_key" ] && continue
  drawer_count=$((drawer_count + 1))
  # Bottom-bar drawers use a compact tip (no Contains:) so Plasma does not clip
  # tall popups off the bottom edge (Waybar#3356).
  case "$drawer_key" in
    custom/dock-drawer | custom/tools-drawer | custom/infra-drawer | \
      custom/security-drawer | custom/hardware-drawer | custom/cooling-drawer)
      if ! echo "$clean_drawers" | jq -e --arg k "$drawer_key" '
        .[$k].tooltip == true
        and (.[$k] | has("exec") | not)
        and (.[$k]["return-type"] != "json")
        and (.[$k]["tooltip-format"]|type)=="string"
        and (.[$k]["tooltip-format"]|contains("Click to toggle"))
        and ((.[$k]["tooltip-format"]|contains("Contains:"))|not)
        and ((.[$k]["tooltip-format"]|contains("Click to expand"))|not)
        and (.[$k].format|type)=="string"
        and (.[$k].format|length)>0
        and .[$k]["tooltip-format"] != .[$k].format
      ' >/dev/null 2>&1; then
        echo "FAIL: $drawer_key must use compact bottom-bar tooltip (no Contains:)" >&2
        echo "$clean_drawers" | jq --arg k "$drawer_key" '.[$k]' >&2
        fail=1
      fi
      ;;
    *)
      if ! echo "$clean_drawers" | jq -e --arg k "$drawer_key" '
        .[$k].tooltip == true
        and (.[$k] | has("exec") | not)
        and (.[$k]["return-type"] != "json")
        and (.[$k]["tooltip-format"]|type)=="string"
        and (.[$k]["tooltip-format"]|contains("Contains:"))
        and (.[$k]["tooltip-format"]|contains("Click to toggle"))
        and ((.[$k]["tooltip-format"]|contains("Click to expand"))|not)
        and (.[$k].format|type)=="string"
        and (.[$k].format|length)>0
        and .[$k]["tooltip-format"] != .[$k].format
      ' >/dev/null 2>&1; then
        echo "FAIL: $drawer_key must use static format + tooltip:true + descriptive tooltip-format (no exec/json)" >&2
        echo "$clean_drawers" | jq --arg k "$drawer_key" '.[$k]' >&2
        fail=1
      fi
      ;;
  esac
done <<<"$drawer_keys"
if [ "$drawer_count" -lt 8 ]; then
  # Settings SoT currently defines ≥8 drawer sides; fewer means a generate miss.
  echo "FAIL: expected at least 8 drawer modules, found $drawer_count" >&2
  fail=1
fi

# Content contracts: top-bar drawers keep Contains:; bottom-bar drawers are compact.
hw_tip=$(echo "$clean_drawers" | jq -r '."custom/hardware-drawer"."tooltip-format"')
if ! printf '%s' "$hw_tip" | grep -qE 'Hardware'; then
  echo "FAIL: hardware-drawer tooltip missing Hardware title: $hw_tip" >&2
  fail=1
fi
if printf '%s' "$hw_tip" | grep -q 'Contains:'; then
  echo "FAIL: hardware-drawer (bottom) must omit Contains: list: $hw_tip" >&2
  fail=1
fi
desk_tip=$(echo "$clean_drawers" | jq -r '."custom/desk-drawer"."tooltip-format"')
if ! printf '%s' "$desk_tip" | grep -q 'Notifications'; then
  echo "FAIL: desk-drawer tooltip missing Notifications: $desk_tip" >&2
  fail=1
fi
devices_tip=$(echo "$clean_drawers" | jq -r '."custom/devices-drawer"."tooltip-format" // empty')
if [ -z "$devices_tip" ] || ! printf '%s' "$devices_tip" | grep -qiE 'Bluetooth|Stream Deck|KDE Connect'; then
  echo "FAIL: devices-drawer tooltip missing peripheral contents: $devices_tip" >&2
  fail=1
fi
cooling_tip=$(echo "$clean_drawers" | jq -r '."custom/cooling-drawer"."tooltip-format" // empty')
if [ -z "$cooling_tip" ] || ! printf '%s' "$cooling_tip" | grep -qiE 'Cooling'; then
  echo "FAIL: cooling-drawer tooltip missing Cooling title: $cooling_tip" >&2
  fail=1
fi
if printf '%s' "$cooling_tip" | grep -q 'Contains:'; then
  echo "FAIL: cooling-drawer (bottom) must omit Contains: list: $cooling_tip" >&2
  fail=1
fi
security_tip=$(echo "$clean_drawers" | jq -r '."custom/security-drawer"."tooltip-format" // empty')
if [ -z "$security_tip" ] || ! printf '%s' "$security_tip" | grep -q 'Security'; then
  echo "FAIL: security-drawer tooltip missing Security title: $security_tip" >&2
  fail=1
fi
if printf '%s' "$security_tip" | grep -q 'Contains:'; then
  echo "FAIL: security-drawer (bottom) must omit Contains: list: $security_tip" >&2
  fail=1
fi
tools_tip=$(echo "$clean_drawers" | jq -r '."custom/tools-drawer"."tooltip-format" // empty')
if [ -z "$tools_tip" ] || ! printf '%s' "$tools_tip" | grep -q 'Quick tools\|Tools'; then
  echo "FAIL: tools-drawer tooltip missing tools title: $tools_tip" >&2
  fail=1
fi
if printf '%s' "$tools_tip" | grep -q 'Contains:'; then
  echo "FAIL: tools-drawer (bottom) must omit Contains: list: $tools_tip" >&2
  fail=1
fi
infra_github=$(echo "$clean_drawers" | jq -r '."custom/infra-drawer"."tooltip-format" // empty')
if printf '%s' "$infra_github" | grep -q 'GitHub'; then
  echo "FAIL: infra-drawer should not list GitHub (moved to tools): $infra_github" >&2
  fail=1
fi
if printf '%s' "$infra_github" | grep -q 'Contains:'; then
  echo "FAIL: infra-drawer (bottom) must omit Contains: list: $infra_github" >&2
  fail=1
fi
desk_vaults=$(printf '%s' "$desk_tip")
if printf '%s' "$desk_vaults" | grep -q 'Vaults'; then
  echo "FAIL: desk-drawer should not list Vaults (moved to security): $desk_tip" >&2
  fail=1
fi

# Pango: bare & in tooltip-format crashes Gtk tooltip markup (Media & volume).
media_tip=$(echo "$clean_drawers" | jq -r '."custom/media-drawer"."tooltip-format"')
if printf '%s' "$media_tip" | grep -qF 'Media & volume'; then
  echo "FAIL: media-drawer tooltip must Pango-escape ampersand: $media_tip" >&2
  fail=1
fi
if ! printf '%s' "$media_tip" | grep -qF 'Media &amp; volume'; then
  echo "FAIL: media-drawer tooltip expected Media &amp; volume: $media_tip" >&2
  fail=1
fi

# Any drawer tooltip with a bare & (not an entity) will break Waybar tooltips.
while IFS= read -r tip; do
  [ -n "$tip" ] || continue
  # Strip known safe entities, then reject remaining &.
  stripped=$(printf '%s' "$tip" | sed -e 's/&amp;/ /g' -e 's/&lt;/ /g' -e 's/&gt;/ /g' -e 's/&#[0-9]*;//g')
  if printf '%s' "$stripped" | grep -q '&'; then
    echo "FAIL: drawer tooltip has unescaped ampersand: $tip" >&2
    fail=1
  fi
done < <(echo "$clean_drawers" | jq -r 'to_entries[] | select(.key|test("drawer")) | .value["tooltip-format"] // empty')

# Side-info retirement: summary tabs must stay off the infra drawer / system modules.
waybar_test_assert_json_file_jq \
  "$TEST_DIR/modules/groups.generated.jsonc" \
  '(."group/infra".modules | index("custom/system") == null) and (."group/infra".modules | index("custom/network") == null)' \
  "retired side-info modules custom/system or custom/network still on group/infra"
infra_tip=$(echo "$clean_drawers" | jq -r '."custom/infra-drawer"."tooltip-format"')
if printf '%s' "$infra_tip" | grep -qE 'Network summary|(^|·) System( ·|$)'; then
  echo "FAIL: infra-drawer tooltip still mentions retired side-info labels: $infra_tip" >&2
  fail=1
fi
waybar_test_assert_json_file_jq \
  "$TEST_DIR/modules/system.generated.jsonc" \
  '(has("custom/system") | not) and (has("custom/network") | not)' \
  "system.generated.jsonc still defines retired custom/system or custom/network"
waybar_test_assert_json_file_jq \
  "$TEST_DIR/data/waybar-settings.json" \
  '(.module_intervals | has("system_tab") or has("network_tab") or has("updates_tab") | not)
   and (.signals | has("active_window") | not)' \
  "settings still have retired side-info intervals or active_window signal"
if [ -d "$TEST_DIR/scripts/side-info" ] || [ -f "$TEST_DIR/scripts/lib/side-info-helpers.sh" ]; then
  echo "FAIL: side-info scripts still present in sandbox tree" >&2
  fail=1
fi

# Explicit negative cases: these shapes must be rejected by validate_custom_module_configs
drawer_bad_dir=$(mktemp -d)
printf '%s\n' '{"custom/desk-drawer":{"format":"X","tooltip":true,"return-type":"json","interval":"once","exec":"printf hi"}}' >"$drawer_bad_dir/exec.jsonc"
if validate_custom_module_configs "$drawer_bad_dir/exec.jsonc" >/dev/null 2>&1; then
  echo "FAIL: validate_custom_module_configs should reject drawer modules that use exec" >&2
  fail=1
fi
printf '%s\n' '{"custom/desk-drawer":{"format":"X","tooltip":"Session controls · click to expand"}}' >"$drawer_bad_dir/string-tip.jsonc"
if validate_custom_module_configs "$drawer_bad_dir/string-tip.jsonc" >/dev/null 2>&1; then
  echo "FAIL: validate_custom_module_configs should reject drawer modules with string tooltip" >&2
  fail=1
fi
printf '%s\n' '{"custom/desk-drawer":{"format":"X","tooltip":true,"tooltip-format":"Hardware\nContains: CPU\nClick to expand"}}' >"$drawer_bad_dir/expand.jsonc"
if validate_custom_module_configs "$drawer_bad_dir/expand.jsonc" >/dev/null 2>&1; then
  echo "FAIL: validate_custom_module_configs should reject 'Click to expand' on drawers" >&2
  fail=1
fi
printf '%s\n' '{"custom/desk-drawer":{"format":"X","tooltip":true,"tooltip-format":"Session controls\nContains: Notifications\nClick to toggle"}}' >"$drawer_bad_dir/ok.jsonc"
if ! validate_custom_module_configs "$drawer_bad_dir/ok.jsonc" >/dev/null 2>&1; then
  echo "FAIL: validate_custom_module_configs rejected a valid static drawer tooltip config" >&2
  fail=1
fi
rm -rf "$drawer_bad_dir"

# Compiled settings SoT contracts
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" 'has("poll_intervals")|not' "compiled waybar-settings.json still has poll_intervals"
# layer=overlay favors KWin tooltips; layer=top lets fullscreen cover the bar.
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" '(.bars.layer == "overlay" or .bars.layer == "top") and .bars.tooltip == true' "expected bars.layer overlay|top and tooltip=true in compiled settings"
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" '.module_intervals.network_bandwidth == 5' "expected module_intervals.network_bandwidth == 5"

# jsonc overwrites json (SoT)
printf '%s\n' '{"bars":{"layer":"top","tooltip":false},"module_intervals":{"weather":123}}' >"$TEST_DIR/data/waybar-settings.json"
printf '%s\n' '{"bars":{"layer":"overlay","tooltip":true},"module_intervals":{"weather":1800}}' >"$TEST_DIR/data/waybar-settings.jsonc"
WAYBAR_HOME="$TEST_DIR" bash -c ". '$TEST_DIR/scripts/lib/waybar-settings.sh'; waybar_settings_get '.bars.layer' 'missing'" >/tmp/waybar-sot-layer.$$
sot_layer=$(cat /tmp/waybar-sot-layer.$$)
rm -f /tmp/waybar-sot-layer.$$
if [ "$sot_layer" != "overlay" ]; then
  echo "FAIL: jsonc SoT did not win over stale json (got layer=$sot_layer)" >&2
  fail=1
fi
# Restore real settings from repo copy for subsequent gens
cp -f data/waybar-settings.jsonc "$TEST_DIR/data/waybar-settings.jsonc"
WAYBAR_HOME="$TEST_DIR" bash -c ". '$TEST_DIR/scripts/lib/waybar-settings.sh'" >/dev/null

# waybar_module_interval reads module_intervals ("once" → long cache TTL)
ttl_weather=$(WAYBAR_HOME="$TEST_DIR" bash -c ". '$TEST_DIR/scripts/lib/waybar-cache-helpers.sh'; waybar_module_interval weather 999")
ttl_once=$(WAYBAR_HOME="$TEST_DIR" bash -c ". '$TEST_DIR/scripts/lib/waybar-cache-helpers.sh'; waybar_module_interval keyboard_layout 42")
ttl_missing=$(WAYBAR_HOME="$TEST_DIR" bash -c ". '$TEST_DIR/scripts/lib/waybar-cache-helpers.sh'; waybar_module_interval totally_missing_key_xyz 77")
if [ "$ttl_weather" != "1800" ]; then
  echo "FAIL: waybar_module_interval weather expected 1800 got $ttl_weather" >&2
  fail=1
fi
# keyboard_layout is "once" in settings → long TTL (not the short fallback)
if [ "$ttl_once" != "86400" ]; then
  echo "FAIL: waybar_module_interval once-key should return 86400 got $ttl_once" >&2
  fail=1
fi
if [ "$ttl_missing" != "77" ]; then
  echo "FAIL: waybar_module_interval missing key expected fallback 77 got $ttl_missing" >&2
  fail=1
fi
# bash alias in waybar-settings.sh
ttl_alias=$(WAYBAR_HOME="$TEST_DIR" bash -c ". '$TEST_DIR/scripts/lib/waybar-settings.sh'; waybar_poll_interval weather 999")
if [ "$ttl_alias" != "1800" ]; then
  echo "FAIL: waybar_poll_interval alias expected 1800 got $ttl_alias" >&2
  fail=1
fi

# Bandwidth module uses module_intervals.network_bandwidth
waybar_test_assert_json_file_jq "$TEST_DIR/modules/network.generated.jsonc" '."network#bandwidthUpBytes".interval == 5' "network bandwidth interval expected 5"

# System custom modules expose tooltip:true
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" '."custom/cpu".tooltip == true and ."custom/syncthing".tooltip == true' "system modules missing tooltip:true"

# Keyboard defaults point at keyboard-layout-click.sh when overrides are null
clean_center_default=$(waybar_test_read_jsonc "$TEST_DIR/modules/center-extras.generated.jsonc")
waybar_test_assert_jq "$clean_center_default" '."custom/keyboard-layout"."on-click" | test("keyboard-layout-click\\.sh next")' "keyboard-layout on-click default missing keyboard-layout-click.sh next"
waybar_test_assert_jq "$clean_center_default" '."custom/keyboard-layout"."on-click-right" | test("keyboard-layout-click\\.sh prev")' "keyboard-layout on-click-right default missing keyboard-layout-click.sh prev"
if [ ! -x "$TEST_DIR/scripts/system/keyboard-layout-click.sh" ]; then
  echo "FAIL: keyboard-layout-click.sh missing or not executable" >&2
  fail=1
fi
if ! sh -n "$TEST_DIR/scripts/system/keyboard-layout-click.sh"; then
  echo "FAIL: keyboard-layout-click.sh failed sh -n" >&2
  fail=1
fi

# Workspaces generated from slot_count; includes point at generated file
slot_count=$(jq -r '.workspaces.slot_count // 5' "$TEST_DIR/data/waybar-settings.json")
if [ ! -f "$TEST_DIR/modules/workspaces.generated.jsonc" ]; then
  echo "FAIL: workspaces.generated.jsonc missing after default generate" >&2
  fail=1
fi
last_slot=$((slot_count - 1))
if ! jq -e --arg k "custom/ws-$last_slot" 'has($k)' "$TEST_DIR/modules/workspaces.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: workspaces.generated.jsonc missing custom/ws-$last_slot for slot_count=$slot_count" >&2
  fail=1
fi
if jq -e --argjson n "$slot_count" 'has("custom/ws-\($n)")' "$TEST_DIR/modules/workspaces.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: workspaces.generated.jsonc has unexpected custom/ws-$slot_count" >&2
  fail=1
fi
if ! grep -q 'workspaces.generated.jsonc' "$TEST_DIR/includes/modules.jsonc"; then
  echo "FAIL: includes/modules.jsonc does not reference workspaces.generated.jsonc" >&2
  fail=1
fi
if grep -q 'modules/workspaces.jsonc"' "$TEST_DIR/includes/modules.jsonc"; then
  echo "FAIL: includes/modules.jsonc still references hand-edited workspaces.jsonc" >&2
  fail=1
fi

# dock-windows enabled by default → bottom center group; active-window remains center
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" '.dock_windows.enabled == true' "expected dock_windows.enabled == true in default settings"
waybar_test_assert_json_file_jq "$TEST_DIR/layouts/bottom.generated.jsonc" \
  '.["modules-center"] | index("group/dock-windows")' \
  "group/dock-windows missing from bottom modules-center (default enabled)"
if jq -e '.["modules-left"] | index("group/dock-windows")' "$TEST_DIR/layouts/bottom.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: group/dock-windows should not be on bottom modules-left" >&2
  fail=1
fi
if jq -e '.["modules-center"] | index("custom/dock-windows")' "$TEST_DIR/layouts/bottom.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: legacy custom/dock-windows should not be on bottom center" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/layouts/bottom.generated.jsonc" '.["modules-center"] | index("custom/active-window")' "custom/active-window missing from bottom modules-center"

echo "PASS: drawer/SoT contracts"
waybar_test_end
