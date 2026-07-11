#!/usr/bin/env bash
# nvme + openlinkhub status/module wiring.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "hw-nvme-olh"
waybar_test_gen_sandbox

echo "Testing nvme and openlinkhub..."
waybar_test_gen_restore_sot
mkdir -p "$TEST_DIR/scripts/system" "$TEST_DIR/scripts/services/openlinkhub"
cp "$ROOT_DIR/scripts/system/nvme-status.sh" "$TEST_DIR/scripts/system/"
cp "$ROOT_DIR/scripts/services/openlinkhub/openlinkhub-status.sh" "$TEST_DIR/scripts/services/openlinkhub/"
waybar_test_chmod_scripts "$TEST_DIR/scripts"

if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before nvme/olh checks" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" '."custom/nvme".exec | test("system/nvme-status\\.sh$")' "custom/nvme exec missing"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" '.["group/hardware"].modules | index("custom/nvme") and index("custom/openlinkhub")' "hardware group missing nvme/openlinkhub"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" '."custom/openlinkhub".exec | test("openlinkhub-status\\.sh$")' "custom/openlinkhub exec missing"

# NVMe fixture hwmon tree
NVME_ROOT="$TEST_DIR/fake-hwmon"
NVME_CACHE="$TEST_DIR/nvme-cache"
mkdir -p "$NVME_ROOT/hwmon0" "$NVME_ROOT/hwmon1" "$NVME_CACHE"
echo nvme >"$NVME_ROOT/hwmon0/name"
echo 37000 >"$NVME_ROOT/hwmon0/temp1_input"
echo Composite >"$NVME_ROOT/hwmon0/temp1_label"
echo nvme >"$NVME_ROOT/hwmon1/name"
echo 67000 >"$NVME_ROOT/hwmon1/temp1_input"
echo Composite >"$NVME_ROOT/hwmon1/temp1_label"
echo 72000 >"$NVME_ROOT/hwmon1/temp2_input"
echo "Sensor 1" >"$NVME_ROOT/hwmon1/temp2_label"
nvme_out=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$NVME_CACHE" \
    WAYBAR_NVME_HWMON_ROOT="$NVME_ROOT" \
    "$TEST_DIR/scripts/system/nvme-status.sh" --refresh
)
if ! echo "$nvme_out" | jq -e '.class == "warning" and (.text | test("67"))' >/dev/null 2>&1; then
  # 67 is composite on hottest drive; warning threshold default 60
  echo "FAIL: nvme-status expected hottest composite 67 warning: $nvme_out" >&2
  fail=1
fi
nvme_empty=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$NVME_CACHE" \
    WAYBAR_NVME_HWMON_ROOT="$TEST_DIR/empty-hwmon" \
    "$TEST_DIR/scripts/system/nvme-status.sh" --refresh
)
mkdir -p "$TEST_DIR/empty-hwmon"
nvme_empty=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$NVME_CACHE" \
    WAYBAR_NVME_HWMON_ROOT="$TEST_DIR/empty-hwmon" \
    "$TEST_DIR/scripts/system/nvme-status.sh" --refresh
)
waybar_test_assert_jq "$nvme_empty" '.class == "disconnected" or (.class|tostring|test("disconnected"))' "empty nvme hwmon should disconnect: $nvme_empty"

# OpenLinkHub fixture — presence-first (device count), exclude cluster
OLH_FIX="$TEST_DIR/olh-api.json"
OLH_CACHE="$TEST_DIR/olh-cache"
mkdir -p "$OLH_CACHE"
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" '.services.openlinkhub.prefer_presence == true' "services.openlinkhub.prefer_presence expected true in compiled settings"
cat >"$OLH_FIX" <<'JSON'
{"device":{
  "cluster":{"ProductType":999,"Product":"Cluster","Serial":"cluster","Hidden":true},
  "a":{"Product":"HX1500i","ProductType":501,"GetDevice":{"IsPSU":true},"Temperature":55},
  "b":{"Product":"Commander","ProductType":1,"Temperature":71}
},"cpuTemp":"48.2"}
JSON
olh_out=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$OLH_CACHE" \
    WAYBAR_OLH_FIXTURE_JSON="$OLH_FIX" \
    WAYBAR_CORSAIRPSU_PRESENT=0 \
    "$TEST_DIR/scripts/services/openlinkhub/openlinkhub-status.sh" --refresh
)
# prefer_presence default: bar shows count (2, cluster excluded), not temp
waybar_test_assert_jq "$olh_out" '(.text | test("2")) and .class == "normal"' "openlinkhub fixture expected presence count 2: $olh_out"
waybar_test_assert_jq "$olh_out" '.tooltip | test("Commander") and test("HX1500i")' "openlinkhub tooltip should list real devices: $olh_out"
if echo "$olh_out" | jq -e '.tooltip | test("Cluster")' >/dev/null 2>&1; then
  echo "FAIL: openlinkhub tooltip must not list cluster: $olh_out" >&2
  fail=1
fi
# prefer_presence=false → bar shows hottest useful temp
OLH_SETTINGS="$OLH_CACHE/settings-home"
mkdir -p "$OLH_SETTINGS/data" "$OLH_SETTINGS/scripts/lib"
cp "$TEST_DIR/data/waybar-settings.json" "$OLH_SETTINGS/data/"
cp "$TEST_DIR/scripts/lib/"*.sh "$OLH_SETTINGS/scripts/lib/" 2>/dev/null || true
jq '.services.openlinkhub.prefer_presence = false' "$OLH_SETTINGS/data/waybar-settings.json" >"$OLH_SETTINGS/data/waybar-settings.json.tmp" \
  && mv "$OLH_SETTINGS/data/waybar-settings.json.tmp" "$OLH_SETTINGS/data/waybar-settings.json"
olh_temp=$(
  WAYBAR_HOME="$OLH_SETTINGS" WAYBAR_SCRIPTS="$OLH_SETTINGS/scripts" XDG_CACHE_HOME="$OLH_CACHE" \
    WAYBAR_OLH_FIXTURE_JSON="$OLH_FIX" \
    WAYBAR_CORSAIRPSU_PRESENT=0 \
    "$TEST_DIR/scripts/services/openlinkhub/openlinkhub-status.sh" --refresh
)
waybar_test_assert_jq "$olh_temp" '(.text | test("71")) and .class == "warning"' "openlinkhub prefer_presence=false expected hot 71 warning: $olh_temp"
# PSU-only + corsairpsu → pointer to PSU module
cat >"$OLH_FIX" <<'JSON'
{"device":{
  "cluster":{"ProductType":999,"Product":"Cluster","Hidden":true},
  "a":{"Product":"HX1500i","ProductType":501,"GetDevice":{"IsPSU":true},"psuTemperature":55.2}
}}
JSON
olh_psu=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$OLH_CACHE" \
    WAYBAR_OLH_FIXTURE_JSON="$OLH_FIX" \
    WAYBAR_CORSAIRPSU_PRESENT=1 \
    "$TEST_DIR/scripts/services/openlinkhub/openlinkhub-status.sh" --refresh
)
waybar_test_assert_jq "$olh_psu" '(.text | test("1")) and (.tooltip | test("PSU module|corsairpsu"; "i"))' "openlinkhub PSU-only should point at PSU module: $olh_psu"
# corsairpsu via fake hwmon tree
OLH_HWMON="$OLH_CACHE/hwmon"
mkdir -p "$OLH_HWMON/hwmon0"
echo corsairpsu >"$OLH_HWMON/hwmon0/name"
olh_hwmon=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$OLH_CACHE" \
    WAYBAR_OLH_FIXTURE_JSON="$OLH_FIX" \
    WAYBAR_HWMON_ROOT="$OLH_HWMON" \
    "$TEST_DIR/scripts/services/openlinkhub/openlinkhub-status.sh" --refresh
)
waybar_test_assert_jq "$olh_hwmon" '.tooltip | test("PSU module|corsairpsu"; "i")' "openlinkhub should detect corsairpsu via WAYBAR_HWMON_ROOT: $olh_hwmon"
olh_down=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$OLH_CACHE" \
    WAYBAR_OLH_API_URL="http://127.0.0.1:9" \
    WAYBAR_OLH_FORCE_ACTIVE=0 \
    "$TEST_DIR/scripts/services/openlinkhub/openlinkhub-status.sh" --refresh
)
waybar_test_assert_jq "$olh_down" '.class == "disconnected" or (.class|tostring|test("disconnected"))' "openlinkhub inactive should disconnect: $olh_down"

echo "PASS: nvme/openlinkhub"
waybar_test_end
