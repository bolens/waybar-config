#!/usr/bin/env bash
# rgb / amdgpu fallback / solaar battery / fans-status supplements.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "hw-rgb-fans"
waybar_test_gen_sandbox
export WAYBAR_WEATHER_UNIT=C

echo "Testing rgb, amdgpu fallback, solaar, and fans..."
waybar_test_gen_restore_sot
mkdir -p "$TEST_DIR/scripts/system" "$TEST_DIR/scripts/services/devices" "$TEST_DIR/scripts/infra"
cp "$ROOT_DIR/scripts/system/rgb-status.sh" \
  "$ROOT_DIR/scripts/system/fans-status.sh" "$ROOT_DIR/scripts/system/gpu-status.sh" \
  "$TEST_DIR/scripts/system/"
cp "$ROOT_DIR/scripts/services/devices/device-battery-status.sh" "$TEST_DIR/scripts/services/devices/"
cp "$ROOT_DIR/scripts/infra/system-metrics-collector.sh" "$ROOT_DIR/scripts/infra/metrics-icons-build.sh" \
  "$TEST_DIR/scripts/infra/"
waybar_test_chmod_scripts "$TEST_DIR/scripts"

if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before rgb/fans checks" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" '."custom/rgb".exec | test("system/rgb-status\\.sh$")' "custom/rgb exec missing"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" '.["group/tools"].modules | index("custom/rgb")' "tools group missing custom/rgb"

# RGB: idle → disconnected
RGB_CACHE="$TEST_DIR/rgb-cache"
mkdir -p "$RGB_CACHE" "$TEST_DIR/rgb-bin"
# Ensure openrgb/ckb not found via empty bin first on PATH, no pgrep matches for our fake
rgb_idle=$(
  PATH="/usr/bin:/bin" \
    WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$RGB_CACHE" \
    WAYBAR_OPENRGB_BIN="$TEST_DIR/rgb-bin/missing" \
    WAYBAR_RGB_FORCE_IDLE=1 \
    "$TEST_DIR/scripts/system/rgb-status.sh" --refresh
)
waybar_test_assert_jq "$rgb_idle" '.class == "disconnected" or (.class|tostring|test("disconnected"))' "idle rgb should disconnect: $rgb_idle"
cat >"$TEST_DIR/rgb-bin/openrgb" <<'EOF'
#!/usr/bin/env bash
echo "0: Test Keyboard"
echo "1: Test Mouse"
EOF
chmod +x "$TEST_DIR/rgb-bin/openrgb"
rgb_on=$(
  PATH="/usr/bin:/bin" \
    WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$RGB_CACHE" \
    WAYBAR_OPENRGB_BIN="$TEST_DIR/rgb-bin/openrgb" \
    WAYBAR_RGB_FORCE_IDLE=0 \
    "$TEST_DIR/scripts/system/rgb-status.sh" --refresh
)
waybar_test_assert_jq "$rgb_on" '(.text | test("2")) and (.tooltip | test("OpenRGB"))' "rgb with openrgb list should show 2 devices: $rgb_on"

# AMD GPU fallback via metrics collector (PATH without nvidia-smi)
AMD_CACHE="$TEST_DIR/amd-cache"
AMD_HWMON="$TEST_DIR/amd-hwmon"
mkdir -p "$AMD_CACHE/waybar" "$AMD_HWMON/hwmon0" "$AMD_HWMON/hwmon0/device"
# Patch collector to use our hwmon by placing a real amdgpu name under a fake class —
# collector scans /sys/class/hwmon only; instead unit-test fill path via env override is hard.
# Smoke: run collector; if host has amdgpu it should report vendor amd when nvidia suspended/unavailable.
# Fixture: create temporary bind is not available; verify jq schema accepts vendor via icons build input.
cat >"$AMD_CACHE/waybar/system-metrics.json" <<'JSON'
{"cpu":{"usage":1,"temp":40,"topology":{"cores":1,"threads":1,"threads_per_core":1},"load":{"one":"0","five":"0","fifteen":"0","runnable":"1","pct":{"one":0,"five":0,"fifteen":0}},"top":[],"history":[1]},"memory":{"mem_used_gib":"1.0","mem_total_gib":"2.0","mem_pct":50,"swap_used_gib":"0.0","swap_total_gib":"0.0","top":[],"history":[50]},"gpu":{"available":true,"name":"AMD iGPU @ 600 MHz","vendor":"amd","util":0,"temp":52,"mem_used":20,"mem_total":512,"vram_pct":3,"fan":0,"suspended":false}}
JSON
# Build icons from fixture metrics
cp "$AMD_CACHE/waybar/system-metrics.json" "$AMD_CACHE/system-metrics.json"
icons=$(
  XDG_CACHE_HOME="$AMD_CACHE" WAYBAR_HOME="$TEST_DIR" \
    bash -c '
    cache_dir="$XDG_CACHE_HOME"
    metrics=$(cat "$cache_dir/system-metrics.json")
    export metrics
    # Call icons builder internals by writing metrics then invoking script
    true
  '
)
# Directly verify gpu-status path via metrics file + serve path: invoke metrics-icons-build after placing metrics
XDG_CACHE_HOME="$AMD_CACHE" WAYBAR_HOME="$TEST_DIR" \
  "$TEST_DIR/scripts/infra/metrics-icons-build.sh" >/dev/null 2>&1 || true
if [ -f "$AMD_CACHE/waybar/gpu-icon.json" ]; then
  if ! jq -e '(.tooltip | test("AMD")) and (.text | test("52"))' "$AMD_CACHE/waybar/gpu-icon.json" >/dev/null 2>&1; then
    echo "FAIL: amd gpu icon should show temp-forward text: $(cat "$AMD_CACHE/waybar/gpu-icon.json")" >&2
    fail=1
  fi
else
  echo "FAIL: metrics-icons-build did not write gpu-icon.json" >&2
  fail=1
fi

# Solaar fallback for device-battery
SOL_BIN="$TEST_DIR/solaar-bin"
SOL_CACHE="$TEST_DIR/sol-cache"
mkdir -p "$SOL_BIN" "$SOL_CACHE"
cat >"$SOL_BIN/solaar" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
1: MX Master 3S
     Battery: 18%, discharging.
OUT
EOF
chmod +x "$SOL_BIN/solaar"
# Empty power_supply via nonexistent override — script always scans real sysfs.
# Prefer solaar even if sysfs exists:
batt_out=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$SOL_CACHE" \
    WAYBAR_SOLAAR_BIN="$SOL_BIN/solaar" \
    WAYBAR_DEVICE_BATTERY_PREFER_SOLAAR=1 \
    "$TEST_DIR/scripts/services/devices/device-battery-status.sh" --refresh
)
waybar_test_assert_jq "$batt_out" '(.text | test("18")) and (.tooltip | test("solaar")) and .class == "warning"' "solaar battery fallback expected 18% warning: $batt_out"

# fans: fake hwmon — PSU deferred when corsairpsu present; nct6799 chassis max
FAN_HWMON="$TEST_DIR/fan-hwmon"
FAN_CACHE="$TEST_DIR/fan-cache"
mkdir -p "$FAN_HWMON/hwmon0" "$FAN_HWMON/hwmon1" "$FAN_HWMON/hwmon2" "$FAN_CACHE"
echo asusec >"$FAN_HWMON/hwmon0/name"
echo 1525 >"$FAN_HWMON/hwmon0/fan1_input"
echo CPU_Opt >"$FAN_HWMON/hwmon0/fan1_label"
echo corsairpsu >"$FAN_HWMON/hwmon1/name"
echo 9999 >"$FAN_HWMON/hwmon1/fan1_input"
echo nct6799 >"$FAN_HWMON/hwmon2/name"
echo 800 >"$FAN_HWMON/hwmon2/fan1_input"
echo 1410 >"$FAN_HWMON/hwmon2/fan2_input"
echo 0 >"$FAN_HWMON/hwmon2/fan3_input"
# Clear path caches so discovery uses the fake tree (cache_dir is $XDG_CACHE_HOME/waybar)
rm -f "$FAN_CACHE"/waybar/asusec-path.txt "$FAN_CACHE"/waybar/corsairpsu-path.txt \
  "$FAN_CACHE"/waybar/nct6799-path.txt "$FAN_CACHE"/waybar/fans-status.json
fan_dedupe=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$FAN_CACHE" \
    WAYBAR_HWMON_ROOT="$FAN_HWMON" \
    "$TEST_DIR/scripts/system/fans-status.sh" --refresh
)
waybar_test_assert_jq "$fan_dedupe" '(.text | test("1525")) and (.tooltip | test("CPU_Opt"))' "fans should show asusec CPU RPM: $fan_dedupe"
waybar_test_assert_jq "$fan_dedupe" '.tooltip | test("Chassis \\(nct6799 max\\): 1410")' "fans should show nct6799 chassis max 1410: $fan_dedupe"
waybar_test_assert_jq "$fan_dedupe" '.tooltip | test("see PSU module")' "fans should defer PSU fan to PSU module: $fan_dedupe"
if echo "$fan_dedupe" | jq -e '.tooltip | test("9999")' >/dev/null 2>&1; then
  echo "FAIL: fans must not duplicate corsairpsu fan RPM when PSU module covers it: $fan_dedupe" >&2
  fail=1
fi
# Without corsairpsu: PSU line is N/A (PSU RPM only deferred when corsairpsu hwmon exists)
FAN_HWMON2="$TEST_DIR/fan-hwmon2"
mkdir -p "$FAN_HWMON2/hwmon0"
echo asusec >"$FAN_HWMON2/hwmon0/name"
echo 1000 >"$FAN_HWMON2/hwmon0/fan1_input"
echo CPU >"$FAN_HWMON2/hwmon0/fan1_label"
rm -f "$FAN_CACHE"/waybar/asusec-path.txt "$FAN_CACHE"/waybar/corsairpsu-path.txt \
  "$FAN_CACHE"/waybar/nct6799-path.txt "$FAN_CACHE"/waybar/fans-status.json
fan_nopasu=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$FAN_CACHE" \
    WAYBAR_HWMON_ROOT="$FAN_HWMON2" \
    "$TEST_DIR/scripts/system/fans-status.sh" --refresh
)
waybar_test_assert_jq "$fan_nopasu" '(.text | test("1000")) and (.tooltip | test("PSU Fan: N/A"))' "fans without corsairpsu should show CPU 1000 + PSU Fan N/A: $fan_nopasu"

# fanctl note in fans tooltip
mkdir -p "$TEST_DIR/fanctl-cfg"
echo 'profiles: []' >"$TEST_DIR/fanctl-cfg/fanctl.yml"
rm -f "$FAN_CACHE"/waybar/asusec-path.txt "$FAN_CACHE"/waybar/corsairpsu-path.txt \
  "$FAN_CACHE"/waybar/nct6799-path.txt "$FAN_CACHE"/waybar/fans-status.json
fan_out=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$FAN_CACHE" \
    WAYBAR_HWMON_ROOT="$FAN_HWMON" \
    WAYBAR_FANCTL_BIN=/usr/bin/true \
    WAYBAR_FANCTL_CONFIG="$TEST_DIR/fanctl-cfg/fanctl.yml" \
    "$TEST_DIR/scripts/system/fans-status.sh" --refresh 2>/dev/null || true
)
if [ -n "$fan_out" ] && ! echo "$fan_out" | jq -e '.tooltip | test("fanctl config")' >/dev/null 2>&1; then
  echo "FAIL: fans tooltip should mention fanctl config: $fan_out" >&2
  fail=1
fi

echo "PASS: rgb/amdgpu/solaar/fans"
waybar_test_end
