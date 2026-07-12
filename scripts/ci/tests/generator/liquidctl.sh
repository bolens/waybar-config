#!/usr/bin/env bash
# liquidctl module wiring and status script behavior.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "liquidctl"
waybar_test_gen_sandbox
export WAYBAR_WEATHER_UNIT=C

# liquidctl module: generator wiring + status script behavior (fixture CLI)
echo "Testing liquidctl module wiring and status script..."
if ! waybar_test_gen_default; then
  echo "FAIL: generate-settings.sh failed before liquidctl checks" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" '."custom/liquidctl".exec | test("system/liquidctl-status\\.sh$")' "custom/liquidctl exec missing system/liquidctl-status.sh"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" '."custom/liquidctl".interval == 60' "custom/liquidctl interval expected 60 from module_intervals.liquidctl"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" '."custom/liquidctl"."on-click-middle" | test("liquidctl-status\\.sh --refresh")' "custom/liquidctl middle-click should refresh"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" '.["group/cooling"].modules | index("custom/liquidctl")' "custom/liquidctl missing from group/cooling modules"
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" '.module_intervals.liquidctl == 60' "module_intervals.liquidctl expected 60 in compiled settings"
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" '.thresholds.liquidctl.temp.warning == 55 and .thresholds.liquidctl.temp.critical == 65' "thresholds.liquidctl.temp missing/wrong in compiled settings"
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" '.liquidctl.skip_corsair_psu_if_hwmon == true' "liquidctl.skip_corsair_psu_if_hwmon expected true in compiled settings"
if [ ! -x "$TEST_DIR/scripts/system/liquidctl-status.sh" ]; then
  echo "FAIL: liquidctl-status.sh missing or not executable" >&2
  fail=1
fi
if ! bash -n "$TEST_DIR/scripts/system/liquidctl-status.sh"; then
  echo "FAIL: liquidctl-status.sh failed bash -n" >&2
  fail=1
fi

LIQUID_FAKE=$(mktemp -d)
cat >"$LIQUID_FAKE/liquidctl" <<'EOF'
#!/usr/bin/env bash
# Fixture: AIO + RGB-only device (RGB should be ignored)
cat <<'JSON'
[
  {
    "description": "NZXT Kraken X63",
    "bus": "hid",
    "address": "/dev/hidraw0",
    "status": [
      {"key": "Liquid temperature", "value": 56.5, "unit": "°C"},
      {"key": "Fan speed", "value": 1200.0, "unit": "rpm"},
      {"key": "Pump speed", "value": 2150.0, "unit": "rpm"}
    ]
  },
  {
    "description": "ASUS Aura LED Controller",
    "bus": "hid",
    "address": "/dev/hidraw1",
    "status": [
      {"key": "ARGB channels", "value": 3, "unit": ""},
      {"key": "RGB channels", "value": 1, "unit": ""}
    ]
  }
]
JSON
EOF
chmod +x "$LIQUID_FAKE/liquidctl"
LIQUID_CACHE=$(mktemp -d)
liquid_out=$(
  XDG_CACHE_HOME="$LIQUID_CACHE" \
    WAYBAR_HOME="$TEST_DIR" \
    WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    WAYBAR_LIQUIDCTL_BIN="$LIQUID_FAKE/liquidctl" \
    WAYBAR_CORSAIRPSU_PRESENT=0 \
    "$TEST_DIR/scripts/system/liquidctl-status.sh" --refresh
) || true
waybar_test_assert_jq "$liquid_out" '.class == "warning"' "liquidctl-status expected warning class at 56.5°C (warn=55): $liquid_out"
waybar_test_assert_jq "$liquid_out" '.text | test("󰖌")' "liquidctl-status text missing liquidctl icon: $liquid_out"
waybar_test_assert_jq "$liquid_out" '.tooltip | test("Kraken") and (test("ASUS Aura LED Controller") | not)' "liquidctl tooltip should include Kraken and skip Aura-only: $liquid_out"
# Aura devices may be noted as skipped (OpenRGB/ckb), but must not appear as telemetry blocks
waybar_test_assert_jq "$liquid_out" '.tooltip | test("Skipped .*Aura")' "liquidctl tooltip should note skipped Aura RGB devices: $liquid_out"
# Missing binary → disconnected (empty text)
liquid_missing=$(
  XDG_CACHE_HOME="$LIQUID_CACHE" \
    WAYBAR_HOME="$TEST_DIR" \
    WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    WAYBAR_LIQUIDCTL_BIN="$LIQUID_FAKE/no-such-liquidctl" \
    PATH="/usr/bin:/bin" \
    "$TEST_DIR/scripts/system/liquidctl-status.sh" --refresh
) || true
waybar_test_assert_jq "$liquid_missing" '.class == "disconnected" and .text == ""' "liquidctl missing binary should emit disconnected: $liquid_missing"
# Empty status JSON → disconnected
cat >"$LIQUID_FAKE/liquidctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '[]'
EOF
chmod +x "$LIQUID_FAKE/liquidctl"
liquid_empty=$(
  XDG_CACHE_HOME="$LIQUID_CACHE" \
    WAYBAR_HOME="$TEST_DIR" \
    WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    WAYBAR_LIQUIDCTL_BIN="$LIQUID_FAKE/liquidctl" \
    "$TEST_DIR/scripts/system/liquidctl-status.sh" --refresh
) || true
waybar_test_assert_jq "$liquid_empty" '.class == "disconnected"' "liquidctl empty status should emit disconnected: $liquid_empty"
rm -rf "$LIQUID_FAKE" "$LIQUID_CACHE"

# Aura-only → disconnect (prefer OpenRGB); no status HID probe needed beyond list
LIQUID_FAKE=$(mktemp -d)
LIQUID_CACHE=$(mktemp -d)
LIQUID_LOG="$LIQUID_FAKE/calls.log"
: >"$LIQUID_LOG"
cat >"$LIQUID_FAKE/liquidctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$LIQUID_LOG"
args=("\$@")
has_json=0; has_list=0; has_status=0; i=0
while [ \$i -lt \${#args[@]} ]; do
  case "\${args[\$i]}" in --json) has_json=1;; list) has_list=1;; status) has_status=1;; esac
  i=\$((i + 1))
done
if [ "\$has_list" -eq 1 ] && [ "\$has_json" -eq 1 ]; then
  echo '[{"description":"ASUS Aura LED Controller","driver":"AuraLed"}]'
  exit 0
fi
# status must not be required for Aura-only hide path
exit 1
EOF
chmod +x "$LIQUID_FAKE/liquidctl"
liquid_aura=$(
  XDG_CACHE_HOME="$LIQUID_CACHE" \
    WAYBAR_HOME="$TEST_DIR" \
    WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    WAYBAR_LIQUIDCTL_BIN="$LIQUID_FAKE/liquidctl" \
    WAYBAR_CORSAIRPSU_PRESENT=0 \
    "$TEST_DIR/scripts/system/liquidctl-status.sh" --refresh
) || true
waybar_test_assert_jq "$liquid_aura" '.class == "disconnected" and (.tooltip | test("Aura|OpenRGB"; "i"))' "liquidctl Aura-only should disconnect: $liquid_aura"
if grep -q 'status' "$LIQUID_LOG" 2>/dev/null; then
  echo "FAIL: liquidctl Aura-only must not call status (HID). Log:" >&2
  cat "$LIQUID_LOG" >&2 || true
  fail=1
fi
rm -rf "$LIQUID_FAKE" "$LIQUID_CACHE"

# Partial failure: bulk --json suppressed (Aura error), per-device --pick still works
# when Corsair PSU is NOT covered by corsairpsu hwmon.
LIQUID_FAKE=$(mktemp -d)
LIQUID_CACHE=$(mktemp -d)
LIQUID_LOG="$LIQUID_FAKE/calls.log"
: >"$LIQUID_LOG"
cat >"$LIQUID_FAKE/liquidctl" <<EOF
#!/usr/bin/env bash
# Mimic liquidctl: bulk status --json fails when any device errors; per-pick works.
printf '%s\n' "\$*" >>"$LIQUID_LOG"
args=("\$@")
has_json=0
has_list=0
has_status=0
pick=""
i=0
while [ \$i -lt \${#args[@]} ]; do
  case "\${args[\$i]}" in
    --json) has_json=1 ;;
    list) has_list=1 ;;
    status) has_status=1 ;;
    --pick)
      i=\$((i + 1))
      pick="\${args[\$i]:-}"
      ;;
  esac
  i=\$((i + 1))
done
if [ "\$has_list" -eq 1 ] && [ "\$has_json" -eq 1 ]; then
  cat <<'JSON'
[
  {"description":"Corsair HX1500i","driver":"CorsairHidPsu"},
  {"description":"ASUS Aura LED Controller","driver":"AuraLed"}
]
JSON
  exit 0
fi
if [ "\$has_status" -eq 1 ] && [ "\$has_json" -eq 1 ]; then
  if [ -z "\$pick" ]; then
    # Bulk call: Aura would error → liquidctl prints no JSON
    exit 1
  fi
  if [ "\$pick" = "0" ]; then
    cat <<'JSON'
[{"description":"Corsair HX1500i","status":[
  {"key":"VRM temperature","value":51.2,"unit":"°C"},
  {"key":"Total power output","value":154.0,"unit":"W"}
]}]
JSON
    exit 0
  fi
  exit 1
fi
exit 1
EOF
chmod +x "$LIQUID_FAKE/liquidctl"
liquid_partial=$(
  XDG_CACHE_HOME="$LIQUID_CACHE" \
    WAYBAR_HOME="$TEST_DIR" \
    WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    WAYBAR_LIQUIDCTL_BIN="$LIQUID_FAKE/liquidctl" \
    WAYBAR_CORSAIRPSU_PRESENT=0 \
    "$TEST_DIR/scripts/system/liquidctl-status.sh" --refresh
) || true
waybar_test_assert_jq "$liquid_partial" '.class == "normal" and (.tooltip | test("HX1500i")) and (.text | test("󰖌"))' "liquidctl partial-failure fallback should show HX telemetry: $liquid_partial"
# With skips present, must use --pick (not rely on bulk status succeeding)
if ! grep -qE 'status.*--pick|--pick.*' "$LIQUID_LOG" 2>/dev/null; then
  echo "FAIL: liquidctl should probe keepers with --pick when skips apply. Log:" >&2
  cat "$LIQUID_LOG" >&2 || true
  fail=1
fi
# When corsairpsu hwmon covers PSU, liquidctl should hide (no exclusive devices) and never status
: >"$LIQUID_LOG"
liquid_skip_psu=$(
  XDG_CACHE_HOME="$LIQUID_CACHE" \
    WAYBAR_HOME="$TEST_DIR" \
    WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    WAYBAR_LIQUIDCTL_BIN="$LIQUID_FAKE/liquidctl" \
    WAYBAR_CORSAIRPSU_PRESENT=1 \
    "$TEST_DIR/scripts/system/liquidctl-status.sh" --refresh
) || true
waybar_test_assert_jq "$liquid_skip_psu" '.class == "disconnected" and (.tooltip | test("corsairpsu|PSU covered|hwmon"; "i"))' "liquidctl should disconnect when PSU covered by corsairpsu: $liquid_skip_psu"
if grep -q 'status' "$LIQUID_LOG" 2>/dev/null; then
  echo "FAIL: liquidctl must not call status when PSU+Aura covered. Log:" >&2
  cat "$LIQUID_LOG" >&2 || true
  fail=1
fi
# hwmon tree detection (WAYBAR_HWMON_ROOT) also triggers skip
HWMON_TREE="$LIQUID_FAKE/hwmon"
mkdir -p "$HWMON_TREE/hwmon0"
echo corsairpsu >"$HWMON_TREE/hwmon0/name"
: >"$LIQUID_LOG"
liquid_hwmon=$(
  XDG_CACHE_HOME="$LIQUID_CACHE" \
    WAYBAR_HOME="$TEST_DIR" \
    WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    WAYBAR_LIQUIDCTL_BIN="$LIQUID_FAKE/liquidctl" \
    WAYBAR_HWMON_ROOT="$HWMON_TREE" \
    "$TEST_DIR/scripts/system/liquidctl-status.sh" --refresh
) || true
waybar_test_assert_jq "$liquid_hwmon" '.class == "disconnected"' "liquidctl should disconnect via WAYBAR_HWMON_ROOT corsairpsu: $liquid_hwmon"
rm -rf "$LIQUID_FAKE" "$LIQUID_CACHE"
echo "PASS: liquidctl module wiring and status script behavior"
waybar_test_end
