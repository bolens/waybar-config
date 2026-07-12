#!/usr/bin/env bash
# CoolerControl module wiring and fixture status/click behavior.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "coolercontrol-module-wiring"
waybar_test_gen_sandbox
export WAYBAR_WEATHER_UNIT=C

# coolercontrol module: generator wiring + status/click (fixtures)
echo "Testing coolercontrol module wiring and status/click scripts..."
if ! waybar_test_gen_modules; then
  echo "FAIL: generate-settings.sh failed before coolercontrol checks" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" '."custom/coolercontrol".exec | test("services/coolercontrol/coolercontrol-status\\.sh$")' "custom/coolercontrol exec missing coolercontrol-status.sh"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" '."custom/coolercontrol".interval == 60' "custom/coolercontrol interval expected 60 from module_intervals.coolercontrol"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" '."custom/coolercontrol"."on-scroll-up" | test("coolercontrol-click\\.sh next")' "custom/coolercontrol scroll-up should cycle next mode"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" '."custom/coolercontrol"."on-scroll-down" | test("coolercontrol-click\\.sh prev")' "custom/coolercontrol scroll-down should cycle prev mode"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" '."custom/coolercontrol"."on-click-right" | test("coolercontrol-click\\.sh menu")' "custom/coolercontrol right-click should open mode menu"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" '.["group/cooling"].modules | index("custom/coolercontrol")' "custom/coolercontrol missing from group/cooling modules"
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" '.module_intervals.coolercontrol == 60' "module_intervals.coolercontrol expected 60 in compiled settings"
mkdir -p "$TEST_DIR/scripts/services/coolercontrol"
cp "$ROOT_DIR/scripts/services/coolercontrol/coolercontrol-status.sh" \
  "$ROOT_DIR/scripts/services/coolercontrol/coolercontrol-click.sh" \
  "$ROOT_DIR/scripts/services/coolercontrol/coolercontrol-api.py" \
  "$TEST_DIR/scripts/services/coolercontrol/"
chmod +x "$TEST_DIR/scripts/services/coolercontrol/"*
if ! bash -n "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-status.sh"; then
  echo "FAIL: coolercontrol-status.sh failed bash -n" >&2
  fail=1
fi
if ! bash -n "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-click.sh"; then
  echo "FAIL: coolercontrol-click.sh failed bash -n" >&2
  fail=1
fi
python3 -m py_compile "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py"

CC_FIX="$TEST_DIR/cc-fixtures-write"
mkdir -p "$CC_FIX"
cat >"$CC_FIX/status.json" <<'JSON'
{"devices":[{"type":"CPU","type_index":0,"uid":"cpu0","status_history":[{"timestamp":"2026-07-11T00:00:00Z","temps":[{"name":"Package","temp":82.4}],"channels":[{"name":"fan1","rpm":1400,"duty":45.0}]}]}]}
JSON
cat >"$CC_FIX/devices.json" <<'JSON'
{"devices":[{"name":"AMD Ryzen","type":"CPU","type_index":0,"uid":"cpu0","info":{"channels":{},"temps":{},"lighting_speeds":[],"profile_max_length":0,"profile_min_length":0,"temp_max":100,"temp_min":0,"driver_info":{"drv_type":"Kernel","name":null,"version":null,"locations":[]}}}]}
JSON
cat >"$CC_FIX/modes.json" <<'JSON'
{"modes":[{"uid":"mode-quiet","name":"Quiet"},{"uid":"mode-default","name":"Default"},{"uid":"mode-game","name":"Gaming"}]}
JSON
cat >"$CC_FIX/modes_active.json" <<'JSON'
{"current_mode_uid":"mode-default","previous_mode_uid":"mode-quiet"}
JSON
echo 200 >"$CC_FIX/write_http.txt"
CC_CACHE="$TEST_DIR/cc-cache"
mkdir -p "$CC_CACHE"

cc_out=$(
  WAYBAR_HOME="$TEST_DIR" \
    XDG_CACHE_HOME="$CC_CACHE" \
    WAYBAR_CC_FIXTURE_DIR="$CC_FIX" \
    WAYBAR_CC_WRITE_PROBE_TTL=0 \
    "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-status.sh" --refresh
)
waybar_test_assert_jq "$cc_out" '.class | (type == "array" and index("warning") and index("writable"))' "coolercontrol-status expected class [warning, writable]: $cc_out"
waybar_test_assert_jq "$cc_out" '.text | test("82")' "coolercontrol-status text missing hot temp: $cc_out"
waybar_test_assert_jq "$cc_out" '.tooltip | test("AMD Ryzen/Package")' "coolercontrol tooltip should join /devices name: $cc_out"
waybar_test_assert_jq "$cc_out" '.tooltip | test("Mode: Default")' "coolercontrol tooltip should show active mode: $cc_out"
waybar_test_assert_jq "$cc_out" '.tooltip | test("Token: write")' "coolercontrol tooltip should show write token: $cc_out"

# Read-only fixture
CC_FIX_RO="$TEST_DIR/cc-fixtures-ro"
cp -a "$CC_FIX" "$CC_FIX_RO"
echo 403 >"$CC_FIX_RO/write_http.txt"
cc_ro=$(
  WAYBAR_HOME="$TEST_DIR" \
    XDG_CACHE_HOME="$CC_CACHE" \
    WAYBAR_CC_FIXTURE_DIR="$CC_FIX_RO" \
    WAYBAR_CC_WRITE_PROBE_TTL=0 \
    "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-status.sh" --refresh
)
waybar_test_assert_jq "$cc_ro" '.class | (type == "array" and index("warning") and index("readonly"))' "coolercontrol-status expected class [warning, readonly]: $cc_ro"
waybar_test_assert_jq "$cc_ro" '.tooltip | test("read-only")' "readonly tooltip missing: $cc_ro"

# API cycle next (write)
cycle_out=$(
  WAYBAR_CC_FIXTURE_DIR="$CC_FIX" \
    python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" cycle next
)
waybar_test_assert_jq "$cycle_out" '.ok == true and .name == "Gaming" and .uid == "mode-game"' "cycle next from Default should activate Gaming: $cycle_out"
if [[ "$(cat "$CC_FIX/last_activate.txt" 2>/dev/null | tr -d '\n')" != "mode-game" ]]; then
  echo "FAIL: cycle next did not record mode-game activation" >&2
  fail=1
fi

# API cycle rejects read-only
cycle_ro=$(
  WAYBAR_CC_FIXTURE_DIR="$CC_FIX_RO" \
    python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" cycle next
) || true
waybar_test_assert_jq "$cycle_ro" '.ok == false and .error == "read_only"' "cycle with read-only should error read_only: $cycle_ro"

# Click script: read-only next should exit 0 without activating
: >"$CC_FIX_RO/last_activate.txt"
# stub notify-send
mkdir -p "$TEST_DIR/fakebin"
cat >"$TEST_DIR/fakebin/notify-send" <<'EOF'
#!/usr/bin/env sh
echo "NOTIFY:$*" >>"${CC_NOTIFY_LOG:-/dev/null}"
EOF
chmod +x "$TEST_DIR/fakebin/notify-send"
CC_NOTIFY_LOG="$TEST_DIR/cc-notify.log"
: >"$CC_NOTIFY_LOG"
PATH="$TEST_DIR/fakebin:/usr/bin:/bin" \
  WAYBAR_HOME="$TEST_DIR" \
  XDG_CACHE_HOME="$CC_CACHE" \
  WAYBAR_CC_FIXTURE_DIR="$CC_FIX_RO" \
  CC_NOTIFY_LOG="$CC_NOTIFY_LOG" \
  "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-click.sh" next
if [[ -s "$CC_FIX_RO/last_activate.txt" ]]; then
  echo "FAIL: readonly click next should not activate a mode" >&2
  fail=1
fi
if ! grep -qi 'read-only' "$CC_NOTIFY_LOG"; then
  echo "FAIL: readonly click should notify read-only. Log: $(cat "$CC_NOTIFY_LOG")" >&2
  fail=1
fi

# Click script: writable next activates
: >"$CC_NOTIFY_LOG"
rm -f "$CC_FIX/last_activate.txt"
PATH="$TEST_DIR/fakebin:/usr/bin:/bin" \
  WAYBAR_HOME="$TEST_DIR" \
  XDG_CACHE_HOME="$CC_CACHE" \
  WAYBAR_CC_FIXTURE_DIR="$CC_FIX" \
  CC_NOTIFY_LOG="$CC_NOTIFY_LOG" \
  "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-click.sh" next
if [[ "$(cat "$CC_FIX/last_activate.txt" 2>/dev/null | tr -d '\n')" != "mode-game" ]]; then
  echo "FAIL: writable click next should activate Gaming" >&2
  fail=1
fi

# Offline / no fixture → disconnected
cc_missing=$(
  WAYBAR_HOME="$TEST_DIR" \
    XDG_CACHE_HOME="$CC_CACHE" \
    WAYBAR_CC_FORCE_ACTIVE=0 \
    "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-status.sh" --refresh
)
waybar_test_assert_jq "$cc_missing" '.class == "disconnected" or (.class|tostring|test("disconnected"))' "coolercontrol offline should emit disconnected: $cc_missing"

echo "PASS: coolercontrol module wiring/status/click"
waybar_test_end
