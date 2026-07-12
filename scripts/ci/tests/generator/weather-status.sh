#!/usr/bin/env bash
# Weather module wiring + locale-aware status (wttr fixture, no network).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "weather-status"
waybar_test_gen_sandbox
export WAYBAR_WEATHER_UNIT=C

echo "Testing weather module wiring and status script..."
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before weather checks" >&2
  fail=1
fi

waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" \
  '."custom/weather".exec | test("services/apps/weather-status\\.sh$")' \
  "custom/weather exec missing weather-status.sh"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" \
  '."custom/weather".signal == 34' \
  "custom/weather should wire signals.weather"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" \
  '
    (."custom/weather"."on-click-middle" | test("weather-status\\.sh --refresh"))
    and (."custom/weather"."on-click-middle" | test("waybar-signal\\.sh weather"))
  ' \
  "custom/weather middle-click should refresh and signal"

mkdir -p "$TEST_DIR/scripts/services/apps" "$TEST_DIR/bin" "$TEST_DIR/wx-cache"
cp "$ROOT_DIR/scripts/services/apps/weather-status.sh" "$TEST_DIR/scripts/services/apps/"
waybar_test_chmod_scripts "$TEST_DIR/scripts/services/apps"

if ! bash -n "$TEST_DIR/scripts/services/apps/weather-status.sh"; then
  echo "FAIL: weather-status.sh failed bash -n" >&2
  fail=1
fi

WX_FIX="$TEST_DIR/wttr-fixture.json"
cat >"$WX_FIX" <<'JSON'
{
  "current_condition": [{
    "temp_C": "21.4",
    "temp_F": "70",
    "weatherCode": "113",
    "weatherDesc": [{"value": "Sunny"}],
    "humidity": "40",
    "windspeedKmph": "12",
    "windspeedMiles": "7",
    "precipMM": "0.0",
    "precipInches": "0.0"
  }],
  "weather": [
    {
      "maxtempC": "24", "mintempC": "15", "maxtempF": "75", "mintempF": "59",
      "hourly": [
        {"weatherDesc": [{"value": "x"}]},
        {"weatherDesc": [{"value": "x"}]},
        {"weatherDesc": [{"value": "x"}]},
        {"weatherDesc": [{"value": "x"}]},
        {"weatherDesc": [{"value": "Partly cloudy"}]}
      ]
    },
    {
      "maxtempC": "22", "mintempC": "14", "maxtempF": "72", "mintempF": "57",
      "hourly": [
        {"weatherDesc": [{"value": "x"}]},
        {"weatherDesc": [{"value": "x"}]},
        {"weatherDesc": [{"value": "x"}]},
        {"weatherDesc": [{"value": "x"}]},
        {"weatherDesc": [{"value": "Rain"}]}
      ]
    },
    {
      "maxtempC": "20", "mintempC": "12", "maxtempF": "68", "mintempF": "54",
      "hourly": [
        {"weatherDesc": [{"value": "x"}]},
        {"weatherDesc": [{"value": "x"}]},
        {"weatherDesc": [{"value": "x"}]},
        {"weatherDesc": [{"value": "x"}]},
        {"weatherDesc": [{"value": "Cloudy"}]}
      ]
    }
  ]
}
JSON

waybar_test_write_bin_stub curl <<EOF
#!/usr/bin/env sh
cat "$WX_FIX"
EOF

# Skip moon animation; run the fetch callback immediately.
cat >"$TEST_DIR/scripts/lib/unicode-animations-lib.sh" <<'EOF'
#!/usr/bin/env sh
animate_command() {
  shift 3
  "$@"
}
EOF

wx_c=$(
  PATH="$TEST_DIR/bin:$PATH" \
    WAYBAR_HOME="$TEST_DIR" \
    WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CACHE_HOME="$TEST_DIR/wx-cache" \
    WAYBAR_WEATHER_UNIT=C \
    "$TEST_DIR/scripts/services/apps/weather-status.sh" --refresh
)
waybar_test_assert_jq "$wx_c" '.text | test("21°C")' "weather C text expected 21°C: $wx_c"
waybar_test_assert_jq "$wx_c" '.tooltip | test("21°C \\(69°F\\)")' "weather C tooltip dual temp: $wx_c"
waybar_test_assert_jq "$wx_c" '.tooltip | test("15°C - 24°C")' "weather C forecast range: $wx_c"
waybar_test_assert_jq "$wx_c" '.tooltip | test("12 km/h")' "weather C prefers metric wind: $wx_c"
waybar_test_assert_jq "$wx_c" '.class == "normal"' "weather class normal: $wx_c"

wx_f=$(
  PATH="$TEST_DIR/bin:$PATH" \
    WAYBAR_HOME="$TEST_DIR" \
    WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CACHE_HOME="$TEST_DIR/wx-cache-f" \
    WAYBAR_WEATHER_UNIT=F \
    "$TEST_DIR/scripts/services/apps/weather-status.sh" --refresh
)
waybar_test_assert_jq "$wx_f" '.text | test("69°F")' "weather F text expected 69°F: $wx_f"
waybar_test_assert_jq "$wx_f" '.tooltip | test("69°F \\(21°C\\)")' "weather F tooltip dual temp: $wx_f"
waybar_test_assert_jq "$wx_f" '.tooltip | test("7 mph")' "weather F prefers imperial wind: $wx_f"

# Open-Meteo provider path (coords + forecast fixture)
OM_FIX="$TEST_DIR/open-meteo-fixture.json"
cat >"$OM_FIX" <<'JSON'
{
  "current": {
    "temperature_2m": 18.4,
    "relative_humidity_2m": 55,
    "weather_code": 0,
    "wind_speed_10m": 10.0,
    "precipitation": 0.0
  },
  "daily": {
    "weather_code": [0, 3, 61],
    "temperature_2m_max": [22.0, 19.0, 17.0],
    "temperature_2m_min": [12.0, 11.0, 10.0]
  }
}
JSON
waybar_test_compile_settings
jq '.weather.provider = "open-meteo" | .weather.latitude = 40.0 | .weather.longitude = -105.0' \
  "$TEST_DIR/data/waybar-settings.json" >"$TEST_DIR/data/waybar-settings.json.tmp"
mv -f "$TEST_DIR/data/waybar-settings.json.tmp" "$TEST_DIR/data/waybar-settings.json"
cp -f "$TEST_DIR/data/waybar-settings.json" "$TEST_DIR/data/waybar-settings.jsonc"
waybar_test_write_bin_stub curl <<EOF
#!/usr/bin/env sh
cat "$OM_FIX"
EOF
wx_om=$(
  PATH="$TEST_DIR/bin:$PATH" \
    WAYBAR_HOME="$TEST_DIR" \
    WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CACHE_HOME="$TEST_DIR/wx-cache-om" \
    WAYBAR_WEATHER_UNIT=C \
    "$TEST_DIR/scripts/services/apps/weather-status.sh" --refresh
)
waybar_test_assert_jq "$wx_om" '.text | test("18°C")' "open-meteo C text expected 18°C: $wx_om"
waybar_test_assert_jq "$wx_om" '.tooltip | test("Open-Meteo") and test("12°C - 22°C")' "open-meteo tooltip forecast: $wx_om"
waybar_test_assert_jq "$wx_om" '.class == "normal"' "open-meteo class normal: $wx_om"

# Locale lib + Python twin stay aligned for CoolerControl path.
locale_sh=$(
  WAYBAR_WEATHER_UNIT=C bash -c '
    . "'"$TEST_DIR"'/scripts/lib/waybar-locale-lib.sh"
    format_locale_temp 21 short | tr -d "\n"
  '
)
locale_py=$(
  WAYBAR_WEATHER_UNIT=C PYTHONPATH="$TEST_DIR/scripts/lib" python3 -c \
    'from locale_temp import format_locale_temp; print(format_locale_temp(21, unit="C", mode="short"), end="")'
)
if [ "$locale_sh" != "$locale_py" ]; then
  echo "FAIL: format_locale_temp shell/python mismatch: sh=$locale_sh py=$locale_py" >&2
  fail=1
fi

echo "PASS: weather-status"
waybar_test_end
