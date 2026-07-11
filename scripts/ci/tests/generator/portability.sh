#!/usr/bin/env bash
# Portability fixtures (sysfs roots, updates backends, capture XDG, Python XDG).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "portability"
waybar_test_gen_sandbox

# --- Portability fixtures (sysfs roots, updates backends, capture XDG, Python XDG) ---
echo "Verifying portability fixtures..."

# Scripts write under $XDG_CACHE_HOME/waybar/ (not the cache home itself).
PORT_CACHE=$(mktemp -d)
export XDG_CACHE_HOME="$PORT_CACHE"
PORT_WB="$PORT_CACHE/waybar"
mkdir -p "$PORT_WB"

# psu: fake WAYBAR_HWMON_ROOT with corsairpsu → watts text; empty → disconnected.
# corsairpsu-path.txt caches an absolute hwmon path — clear it when swapping trees.
PSU_HWMON=$(mktemp -d)
mkdir -p "$PSU_HWMON/hwmon0"
echo corsairpsu >"$PSU_HWMON/hwmon0/name"
echo 150000000 >"$PSU_HWMON/hwmon0/power1_input"
echo 120000000 >"$PSU_HWMON/hwmon0/power2_input"
echo 10000000 >"$PSU_HWMON/hwmon0/power3_input"
echo 5000000 >"$PSU_HWMON/hwmon0/power4_input"
echo 800 >"$PSU_HWMON/hwmon0/fan1_input"
echo 45000 >"$PSU_HWMON/hwmon0/temp1_input"
echo 40000 >"$PSU_HWMON/hwmon0/temp2_input"
echo 120000 >"$PSU_HWMON/hwmon0/in0_input"
echo 12000 >"$PSU_HWMON/hwmon0/in1_input"
echo 5000 >"$PSU_HWMON/hwmon0/in2_input"
echo 3300 >"$PSU_HWMON/hwmon0/in3_input"
rm -f "$PORT_WB/corsairpsu-path.txt" "$PORT_WB/psu-status.json"
psu_out=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CACHE_HOME="$PORT_CACHE" WAYBAR_HWMON_ROOT="$PSU_HWMON" \
    "$TEST_DIR/scripts/system/psu-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
waybar_test_assert_jq "$psu_out" '.text | test("150W")' "psu WAYBAR_HWMON_ROOT should report 150W: $psu_out"
# Meta-guard: exported poison root must not override an explicit per-command root
# (same bash assignment rule as the CoolerControl fixture meta-guard above).
psu_poison=$(
  export WAYBAR_HWMON_ROOT=/nonexistent-poison-hwmon
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CACHE_HOME="$PORT_CACHE" WAYBAR_HWMON_ROOT="$PSU_HWMON" \
    "$TEST_DIR/scripts/system/psu-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
waybar_test_assert_jq "$psu_poison" '.text | test("150W")' "isolation meta-guard — poisoned WAYBAR_HWMON_ROOT must not override cmdline root: $psu_poison"
unset WAYBAR_HWMON_ROOT || true
PSU_EMPTY=$(mktemp -d)
rm -f "$PORT_WB/corsairpsu-path.txt" "$PORT_WB/psu-status.json"
rm -rf "$PSU_HWMON" # drop cached path target if any residual
psu_empty=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CACHE_HOME="$PORT_CACHE" WAYBAR_HWMON_ROOT="$PSU_EMPTY" \
    "$TEST_DIR/scripts/system/psu-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
waybar_test_assert_jq "$psu_empty" '.class == "disconnected"' "psu empty hwmon should disconnect: $psu_empty"
rm -rf "$PSU_EMPTY"

# device-battery: Device-type battery via WAYBAR_POWER_SUPPLY_ROOT
BATT_ROOT=$(mktemp -d)
mkdir -p "$BATT_ROOT/hidpp_battery_0"
echo Battery >"$BATT_ROOT/hidpp_battery_0/type"
echo Device >"$BATT_ROOT/hidpp_battery_0/scope"
echo 42 >"$BATT_ROOT/hidpp_battery_0/capacity"
echo Discharging >"$BATT_ROOT/hidpp_battery_0/status"
echo "Test Mouse" >"$BATT_ROOT/hidpp_battery_0/model_name"
rm -f "$PORT_WB/device-battery.json"
batt_out=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CACHE_HOME="$PORT_CACHE" WAYBAR_POWER_SUPPLY_ROOT="$BATT_ROOT" \
    PATH="/usr/bin:/bin" \
    "$TEST_DIR/scripts/services/devices/device-battery-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
waybar_test_assert_jq "$batt_out" '(.text | test("42%")) and (.tooltip | test("sysfs"))' "device-battery WAYBAR_POWER_SUPPLY_ROOT: $batt_out"
rm -rf "$BATT_ROOT"

# metrics: k10temp + amdgpu under WAYBAR_HWMON_ROOT
MET_HWMON=$(mktemp -d)
mkdir -p "$MET_HWMON/hwmon0" "$MET_HWMON/hwmon1"
echo k10temp >"$MET_HWMON/hwmon0/name"
echo 52000 >"$MET_HWMON/hwmon0/temp1_input"
echo amdgpu >"$MET_HWMON/hwmon1/name"
echo 61000 >"$MET_HWMON/hwmon1/temp1_input"
echo 500000000 >"$MET_HWMON/hwmon1/power1_average"
rm -f "$PORT_WB"/cpu-temp-path.txt "$PORT_WB"/amdgpu-hwmon-path.txt "$PORT_WB"/system-metrics.json "$PORT_WB"/gpu-pci-path.txt
met_out=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CACHE_HOME="$PORT_CACHE" WAYBAR_HWMON_ROOT="$MET_HWMON" \
    WAYBAR_THERMAL_ROOT="$(mktemp -d)" \
    "$TEST_DIR/scripts/infra/system-metrics-collector.sh" --refresh 2>/dev/null || true
)
if [ ! -f "$PORT_WB/system-metrics.json" ]; then
  echo "FAIL: metrics collector did not write system-metrics.json" >&2
  fail=1
elif ! jq -e '.cpu.temp == 52' "$PORT_WB/system-metrics.json" >/dev/null 2>&1; then
  echo "FAIL: metrics cpu.temp expected 52: $(cat "$PORT_WB/system-metrics.json")" >&2
  fail=1
elif jq -e '.gpu.available == true and .gpu.vendor == "amd"' "$PORT_WB/system-metrics.json" >/dev/null 2>&1; then
  if ! jq -e '.gpu.temp == 61' "$PORT_WB/system-metrics.json" >/dev/null 2>&1; then
    echo "FAIL: metrics amdgpu temp expected 61: $(cat "$PORT_WB/system-metrics.json")" >&2
    fail=1
  fi
elif ! grep -q '0x10de' /sys/bus/pci/devices/*/vendor 2>/dev/null; then
  echo "FAIL: metrics expected amdgpu GPU from WAYBAR_HWMON_ROOT: $(cat "$PORT_WB/system-metrics.json")" >&2
  fail=1
fi
rm -rf "$MET_HWMON"

# updates-status: apt / dnf / none backends via PATH stubs
UPD_BIN=$(mktemp -d)
cat >"$UPD_BIN/apt" <<'EOF'
#!/usr/bin/env sh
if [ "${1:-}" = "list" ]; then
  printf 'Listing...\nfoo/stable 1.0 [upgradable from: 0.9]\nbar/stable 2.0 [upgradable from: 1.9]\n'
fi
EOF
cat >"$UPD_BIN/dnf" <<'EOF'
#!/usr/bin/env sh
printf 'baz.x86_64 1.2-3\nqux.x86_64 4.5-6\n'
exit 100
EOF
cat >"$UPD_BIN/timeout" <<'EOF'
#!/usr/bin/env sh
shift
exec "$@"
EOF
cat >"$UPD_BIN/flatpak" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "$UPD_BIN"/*
rm -f "$PORT_WB/updates-status.json"
apt_upd=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CACHE_HOME="$PORT_CACHE" WAYBAR_UPDATES_BACKEND=apt WAYBAR_BACKGROUND=0 \
    PATH="$UPD_BIN:/usr/bin:/bin" \
    "$TEST_DIR/scripts/services/sync/updates-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
waybar_test_assert_jq "$apt_upd" '(.tooltip | test("APT updates: 2")) and (.tooltip | test("Backend: apt"))' "updates apt backend: $apt_upd"
rm -f "$PORT_WB/updates-status.json"
dnf_upd=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CACHE_HOME="$PORT_CACHE" WAYBAR_UPDATES_BACKEND=dnf WAYBAR_BACKGROUND=0 \
    PATH="$UPD_BIN:/usr/bin:/bin" \
    "$TEST_DIR/scripts/services/sync/updates-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
waybar_test_assert_jq "$dnf_upd" '(.tooltip | test("DNF updates: 2")) and (.tooltip | test("Backend: dnf"))' "updates dnf backend: $dnf_upd"
rm -f "$PORT_WB/updates-status.json"
none_upd=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CACHE_HOME="$PORT_CACHE" WAYBAR_UPDATES_BACKEND=none WAYBAR_BACKGROUND=0 \
    PATH="$UPD_BIN:/usr/bin:/bin" \
    "$TEST_DIR/scripts/services/sync/updates-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
waybar_test_assert_jq "$none_upd" '(.text | test("  0")) and (.tooltip | test("Backend: none"))' "updates none backend should be zero: $none_upd"
rm -rf "$UPD_BIN"

# updates-review: apt path without paru (settings apps.apt_update)
REV_BIN=$(mktemp -d)
REV_HOME=$(mktemp -d)
mkdir -p "$REV_HOME/data" "$REV_HOME/scripts/"{lib,tools,services/sync}
cp "$ROOT_DIR/scripts/services/sync/updates-review.sh" "$REV_HOME/scripts/services/sync/"
cp "$ROOT_DIR/scripts/lib/waybar-settings.sh" \
  "$ROOT_DIR/scripts/lib/compositor-session.sh" \
  "$ROOT_DIR/scripts/lib/app-open-lib.sh" \
  "$REV_HOME/scripts/lib/"
cat >"$REV_HOME/data/waybar-settings.json" <<'JSON'
{
  "apps": { "apt_update": "MOCK_APT_UPGRADE", "terminal": "MOCK_TERM" },
  "rofi": { "updates": { "width": 111, "height": 222 } },
  "updates": { "enable_aur": false }
}
JSON
cat >"$REV_BIN/apt" <<'EOF'
#!/usr/bin/env sh
printf 'pkg/stable 1.0 [upgradable from: 0.9]\n'
EOF
cat >"$REV_BIN/rofi" <<'EOF'
#!/usr/bin/env sh
printf '🚀 Upgrade System Now\n'
EOF
cat >"$REV_BIN/notify-send" <<'EOF'
#!/usr/bin/env sh
:
EOF
chmod +x "$REV_BIN"/*
cat >"$REV_HOME/scripts/tools/app-open.sh" <<EOF
#!/usr/bin/env sh
printf 'app-open %s\n' "\$*" >>"$PORT_CACHE/rev-calls.log"
EOF
chmod +x "$REV_HOME/scripts/tools/app-open.sh" "$REV_HOME/scripts/services/sync/updates-review.sh"
: >"$PORT_CACHE/rev-calls.log"
WAYBAR_HOME="$REV_HOME" WAYBAR_SCRIPTS="$REV_HOME/scripts" \
  WAYBAR_UPDATES_BACKEND=apt PATH="$REV_BIN:/usr/bin:/bin" \
  "$REV_HOME/scripts/services/sync/updates-review.sh" >/dev/null 2>&1 || true
if ! grep -q 'app-open MOCK_APT_UPGRADE' "$PORT_CACHE/rev-calls.log"; then
  echo "FAIL: updates-review apt should use apps.apt_update. log=$(cat "$PORT_CACHE/rev-calls.log" 2>/dev/null)" >&2
  fail=1
fi
rm -rf "$REV_BIN" "$REV_HOME"

# capture-lib: XDG defaults + env overrides
CAP_HOME=$(mktemp -d)
mkdir -p "$CAP_HOME/scripts/lib" "$CAP_HOME/data"
cp "$ROOT_DIR/scripts/lib/capture-lib.sh" "$ROOT_DIR/scripts/lib/waybar-settings.sh" "$CAP_HOME/scripts/lib/"
printf '{"capture":{"screenshot_dir":null,"screenrecord_dir":null,"screenrecord_fps":60}}\n' >"$CAP_HOME/data/waybar-settings.json"
cap_shot=$(
  WAYBAR_HOME="$CAP_HOME" HOME="$CAP_HOME/fakehome" \
    XDG_PICTURES_DIR="$CAP_HOME/Pics" XDG_VIDEOS_DIR="$CAP_HOME/Vids" \
    bash -c '. "$WAYBAR_HOME/scripts/lib/capture-lib.sh"; capture_screenshot_base_dir'
)
cap_rec=$(
  WAYBAR_HOME="$CAP_HOME" HOME="$CAP_HOME/fakehome" \
    XDG_PICTURES_DIR="$CAP_HOME/Pics" XDG_VIDEOS_DIR="$CAP_HOME/Vids" \
    bash -c '. "$WAYBAR_HOME/scripts/lib/capture-lib.sh"; capture_screenrecord_base_dir'
)
if [ "$cap_shot" != "$CAP_HOME/Pics/Screenshots" ] || [ "$cap_rec" != "$CAP_HOME/Vids/Screenrecordings" ]; then
  echo "FAIL: capture XDG defaults: shot=$cap_shot rec=$cap_rec" >&2
  fail=1
fi
cap_env=$(
  WAYBAR_HOME="$CAP_HOME" WAYBAR_SCREENSHOT_DIR="/override/shots" \
    bash -c '. "$WAYBAR_HOME/scripts/lib/capture-lib.sh"; capture_screenshot_base_dir'
)
if [ "$cap_env" != "/override/shots" ]; then
  echo "FAIL: WAYBAR_SCREENSHOT_DIR override: $cap_env" >&2
  fail=1
fi
rm -rf "$CAP_HOME"

# Python: XDG_CONFIG_HOME alone resolves WAYBAR_HOME
PY_XDG=$(mktemp -d)
mkdir -p "$PY_XDG/cfg/waybar/scripts/lib" "$PY_XDG/cfg/waybar/data"
cp "$ROOT_DIR/scripts/system/touchpad.py" "$PY_XDG/"
cp "$ROOT_DIR/scripts/lib/waybar-signal.sh" "$PY_XDG/cfg/waybar/scripts/lib/"
# Smoke: import path resolution by running a one-liner equivalent to touchpad's resolve
py_home=$(
  unset WAYBAR_HOME
  XDG_CONFIG_HOME="$PY_XDG/cfg" python3 - <<'PY'
import os
waybar_home = os.environ.get("WAYBAR_HOME") or os.path.join(
    os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "waybar"
)
print(waybar_home)
PY
)
if [ "$py_home" != "$PY_XDG/cfg/waybar" ]; then
  echo "FAIL: Python XDG_CONFIG_HOME WAYBAR_HOME resolve: $py_home" >&2
  fail=1
fi
# vaults.py / device-notifier same pattern
for pyf in scripts/services/security/vaults.py scripts/services/devices/device-notifier.py; do
  if ! grep -q 'XDG_CONFIG_HOME' "$ROOT_DIR/$pyf"; then
    echo "FAIL: $pyf should honor XDG_CONFIG_HOME" >&2
    fail=1
  fi
done
rm -rf "$PY_XDG" "$PORT_CACHE"

echo "PASS: portability fixtures"
waybar_test_end
