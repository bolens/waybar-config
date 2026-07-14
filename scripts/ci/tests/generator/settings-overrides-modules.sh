#!/usr/bin/env bash
# Settings override wiring for modules / clicks / services.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "settings-overrides-modules"
waybar_test_gen_sandbox
if ! waybar_test_gen_default; then
  echo "FAIL: default generate failed before overrides" >&2
  exit 1
fi

echo "Running behavioral tests for settings overrides..."

# Override settings file with a custom mock containing bars, services, clocks, and theme configurations
cp "$ROOT_DIR/scripts/ci/lib/fixtures/settings/generator-overrides.jsonc" \
  "$TEST_DIR/data/waybar-settings.jsonc"

# Run generators to build settings and rebuild modules
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed with custom configuration" >&2
  exit 1
fi

# Verify settings were compiled to JSON
if [ ! -f "$TEST_DIR/data/waybar-settings.json" ]; then
  echo "FAIL: waybar-settings.json was not compiled from waybar-settings.jsonc" >&2
  fail=1
fi

echo "Validating generated JSONC and CSS files for custom settings overrides..."
validate_all_generated_files "custom settings overrides" || fail=1

# Check that the clock config has our custom format and custom interval
clock_conf="$TEST_DIR/modules/clock.generated.jsonc"
if [ -f "$clock_conf" ]; then
  # Clean comments and parse
  clean_clock=$(waybar_test_read_jsonc "$clock_conf")
  if ! echo "$clean_clock" | jq -e '."clock#bottom".format == "TEST_BOTTOM_CLOCK_FORMAT"' >/dev/null 2>&1; then
    echo "FAIL: Custom clock format not compiled correctly into clock.generated.jsonc" >&2
    echo "Generated output: $clean_clock" >&2
    fail=1
  fi
  if ! echo "$clean_clock" | jq -e '."clock#bottom".interval == 42' >/dev/null 2>&1; then
    echo "FAIL: Custom clock interval not compiled correctly into clock.generated.jsonc" >&2
    fail=1
  fi
  if ! echo "$clean_clock" | jq -e '."clock#bottom".calendar.first_day == 0' >/dev/null 2>&1; then
    echo "FAIL: Calendar first day override was not compiled correctly into clock.generated.jsonc!" >&2
    fail=1
  fi
  if ! echo "$clean_clock" | jq -e '."clock#bottom".locale == "fr_FR.UTF-8"' >/dev/null 2>&1; then
    echo "FAIL: Clocks locale override fr_FR.UTF-8 not compiled correctly into clock.generated.jsonc!" >&2
    fail=1
  fi
else
  echo "FAIL: clock.generated.jsonc was not generated!" >&2
  fail=1
fi

# Assert pulseaudio custom volume settings overrides compiled correctly
audio_conf="$TEST_DIR/modules/audio.generated.jsonc"
echo "=== DEBUG AUDIO CONF PATH: $audio_conf ==="
cat "$audio_conf"
if [ -f "$audio_conf" ]; then
  clean_audio=$(waybar_test_read_jsonc "$audio_conf")
  if ! echo "$clean_audio" | jq -e '.pulseaudio."on-scroll-up" == "wpctl set-volume -l 1.2 @DEFAULT_AUDIO_SINK@ 2%+"' >/dev/null 2>&1; then
    echo "FAIL: Custom pulseaudio on-scroll-up not compiled correctly into audio.generated.jsonc" >&2
    echo "Generated output: $clean_audio" >&2
    fail=1
  fi
  if ! echo "$clean_audio" | jq -e '.pulseaudio."on-scroll-down" == "wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"' >/dev/null 2>&1; then
    echo "FAIL: Custom pulseaudio on-scroll-down not compiled correctly into audio.generated.jsonc" >&2
    fail=1
  fi
  if ! echo "$clean_audio" | jq -e '.pulseaudio."on-click" == "TEST_AUDIO_ON_CLICK"' >/dev/null 2>&1; then
    echo "FAIL: Custom pulseaudio on-click override not compiled correctly into audio.generated.jsonc" >&2
    fail=1
  fi
  if ! echo "$clean_audio" | jq -e '.bluetooth."on-click" == "TEST_BLUETOOTH_ON_CLICK"' >/dev/null 2>&1; then
    echo "FAIL: Custom bluetooth on-click override not compiled correctly into audio.generated.jsonc" >&2
    fail=1
  fi
  if ! echo "$clean_audio" | jq -e '."custom/media-prev"."on-click-right" == "playerctl position 17-"' >/dev/null 2>&1; then
    echo "FAIL: audio.seek_back_sec not wired into media-prev on-click-right" >&2
    fail=1
  fi
  if ! echo "$clean_audio" | jq -e '."custom/media-next"."on-click-right" == "playerctl position 23+"' >/dev/null 2>&1; then
    echo "FAIL: audio.seek_forward_sec not wired into media-next on-click-right" >&2
    fail=1
  fi
else
  echo "FAIL: audio.generated.jsonc was not generated!" >&2
  fail=1
fi

# Verify locale helpers respect overrides
test_hour_fmt=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/lib/waybar-settings.sh; . $TEST_DIR/scripts/lib/waybar-locale-lib.sh; detect_clock_format")
if [ "$test_hour_fmt" != "12" ]; then
  echo "FAIL: detect_clock_format failed to respect clocks.hour_format override! Resolved: $test_hour_fmt" >&2
  fail=1
fi

test_date_fmt=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/lib/waybar-settings.sh; . $TEST_DIR/scripts/lib/waybar-locale-lib.sh; detect_date_format")
if [ "$test_date_fmt" != "month-first" ]; then
  echo "FAIL: detect_date_format failed to respect clocks.date_format override! Resolved: $test_date_fmt" >&2
  fail=1
fi

test_first_day=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/lib/waybar-settings.sh; . $TEST_DIR/scripts/lib/waybar-locale-lib.sh; detect_first_weekday")
if [ "$test_first_day" != "0" ]; then
  echo "FAIL: detect_first_weekday failed to respect clocks.calendar.first_day override! Resolved: $test_first_day" >&2
  fail=1
fi

test_weather_unit=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/lib/waybar-settings.sh; . $TEST_DIR/scripts/lib/waybar-locale-lib.sh; detect_weather_unit")
if [ "$test_weather_unit" != "F" ]; then
  echo "FAIL: detect_weather_unit failed to respect weather.unit override! Resolved: $test_weather_unit" >&2
  fail=1
fi

# Verify active-window-scroll.sh works correctly without zscroll (using zscroll=false, max_length=15 override)
mkdir -p "$TEST_DIR/bin"
cat <<'SH' >"$TEST_DIR/bin/hyprctl"
#!/bin/sh
if [ "$1" = "activewindow" ]; then
  echo '{"title":"Very Long Window Title That Exceeds Fifteen Characters"}'
fi
SH
chmod +x "$TEST_DIR/bin/hyprctl"

out_file="$TEST_DIR/active-window-test.log"
XDG_CACHE_HOME="$TEST_DIR/cache" PATH="$TEST_DIR/bin:$PATH" WAYBAR_HOME="$TEST_DIR" bash "$TEST_DIR/scripts/workspaces/active-window-scroll.sh" >"$out_file" 2>&1 &
sub_pid=$!

# Wait for directory creation and startup, then write test title to cache
sleep 0.3
mkdir -p "$TEST_DIR/cache/waybar"
echo "Very Long Window Title That Exceeds Fifteen Characters" >"$TEST_DIR/cache/waybar/active-window-title.raw"

sleep 0.6
kill "$sub_pid" 2>/dev/null || true

if ! grep -q '"text":"󰖲  Very Long Wi..."' "$out_file"; then
  echo "FAIL: active-window-scroll.sh failed to truncate correctly when zscroll is disabled!" >&2
  cat "$out_file" >&2
  fail=1
fi

# Verify mpris-scroll.sh works correctly without zscroll (using mpris_zscroll=false, mpris_max_length=20 override)
cat <<'SH' >"$TEST_DIR/bin/playerctl"
#!/bin/sh
if [ "$1" = "status" ]; then
  echo "Playing"
elif [ "$1" = "metadata" ]; then
  echo "󰝚 Heavy Metal Song Title That Exceeds Twenty Characters"
fi
SH
chmod +x "$TEST_DIR/bin/playerctl"

out_mpris="$TEST_DIR/mpris-test.log"
PATH="$TEST_DIR/bin:$PATH" WAYBAR_HOME="$TEST_DIR" bash "$TEST_DIR/scripts/media/mpris-scroll.sh" >"$out_mpris" 2>&1 &
mpris_pid=$!

sleep 0.8
kill "$mpris_pid" 2>/dev/null || true

if ! grep -q '󰝚 Heavy Metal Son...' "$out_mpris"; then
  echo "FAIL: mpris-scroll.sh failed to truncate correctly when zscroll is disabled!" >&2
  cat "$out_mpris" >&2
  fail=1
fi

# Assert bar configurations overrides compiled correctly
clean_bar=$(waybar_test_read_jsonc "$TEST_DIR/includes/bar-defaults.generated.jsonc")
waybar_test_assert_jq "$clean_bar" '.height == 99' "Overridden bar height was not compiled correctly into bar-defaults"
waybar_test_assert_jq "$clean_bar" '.spacing == 99' "Overridden bar spacing was not compiled correctly into bar-defaults"

# Assert system services configuration overrides compiled correctly
clean_sys=$(waybar_test_read_jsonc "$TEST_DIR/modules/system.generated.jsonc")
waybar_test_assert_jq "$clean_sys" '."custom/chkrootkit"."on-click" == "TEST_CHKROOTKIT_ON_CLICK"' "Custom chkrootkit on-click override not compiled correctly into system.generated.jsonc"
waybar_test_assert_jq "$clean_sys" '."custom/libredefender"."on-click" == "TEST_LIBREDEFENDER_ON_CLICK"' "Custom libredefender on-click override not compiled correctly into system.generated.jsonc"
waybar_test_assert_jq "$clean_sys" '."custom/syncthing".interval == 77' "Custom syncthing interval override not compiled correctly into system.generated.jsonc"
waybar_test_assert_jq "$clean_sys" '."custom/syncthing".signal == 99' "Custom syncthing signal override not compiled correctly into system.generated.jsonc"
waybar_test_assert_jq "$clean_sys" '."custom/sunshine".interval == 76' "Custom sunshine interval override not compiled correctly into system.generated.jsonc"
waybar_test_assert_jq "$clean_sys" '."custom/sunshine".signal == 98' "Custom sunshine signal override not compiled correctly into system.generated.jsonc"
waybar_test_assert_jq "$clean_sys" '."custom/syncthing"."on-click" == "TEST_SYNCTHING_ON_CLICK"' "Custom syncthing on-click override not compiled correctly into system.generated.jsonc"
waybar_test_assert_jq "$clean_sys" '."custom/syncthing"."on-click-right" | test("MOCK_SYNCTHING")' "services.syncthing.service_name not wired into syncthing on-click-right"
waybar_test_assert_jq "$clean_sys" '."custom/libredefender"."on-click-right" | test("MOCK_TERM")' "apps.terminal not wired into libredefender journalctl fallback"
waybar_test_assert_jq "$clean_sys" '."custom/chkrootkit"."on-click-right" | test("MOCK_TERM")' "apps.terminal not wired into chkrootkit journalctl fallback"
waybar_test_assert_jq "$clean_sys" '."custom/sunshine"."on-click-right" == "TEST_SUNSHINE_ON_CLICK_RIGHT"' "Custom sunshine on-click-right override not compiled correctly into system.generated.jsonc"
waybar_test_assert_jq "$clean_sys" '."custom/disk"."on-click" | test("app-open-key\\.sh file_manager")' "apps.file_manager not wired into custom/disk on-click via app-open-key.sh"
waybar_test_assert_jq "$clean_sys" '."custom/ups"."on-click" | test("app-open-key\\.sh power_settings")' "apps.power_settings not wired into custom/ups on-click via app-open-key.sh"

# Assert weather configurations click action overrides compiled correctly
clean_utils=$(waybar_test_read_jsonc "$TEST_DIR/modules/utilities.generated.jsonc")
waybar_test_assert_jq "$clean_utils" '."custom/weather"."on-click" == "TEST_WEATHER_ON_CLICK"' "Custom weather on-click override not compiled correctly into utilities.generated.jsonc"
waybar_test_assert_jq "$clean_utils" '."custom/weather"."on-click-right" == "TEST_WEATHER_ON_CLICK_RIGHT"' "Custom weather on-click-right override not compiled correctly into utilities.generated.jsonc"
waybar_test_assert_jq "$clean_utils" '."custom/weather"."on-click-middle" == "TEST_WEATHER_ON_CLICK_MIDDLE"' "Custom weather on-click-middle override not compiled correctly into utilities.generated.jsonc"

waybar_test_assert_jq "$clean_utils" '."custom/kdeconnect"."on-click" == "TEST_KDECONNECT_ON_CLICK"' "Custom kdeconnect on-click override not compiled correctly into utilities.generated.jsonc"
waybar_test_assert_jq "$clean_utils" '."custom/kdeconnect"."on-click-right" == "TEST_KDECONNECT_ON_CLICK_RIGHT"' "Custom kdeconnect on-click-right override not compiled correctly into utilities.generated.jsonc"
waybar_test_assert_jq "$clean_utils" '."custom/kdeconnect"."on-click-middle" == "TEST_KDECONNECT_ON_CLICK_MIDDLE"' "Custom kdeconnect on-click-middle override not compiled correctly into utilities.generated.jsonc"

waybar_test_assert_jq "$clean_utils" '."custom/device-notifier"."on-click" == "TEST_DEVICE_NOTIFIER_ON_CLICK"' "Custom device-notifier on-click override not compiled correctly into utilities.generated.jsonc"
waybar_test_assert_jq "$clean_utils" '."custom/device-notifier"."on-click-right" == "TEST_DEVICE_NOTIFIER_ON_CLICK_RIGHT"' "Custom device-notifier on-click-right override not compiled correctly into utilities.generated.jsonc"

waybar_test_assert_jq "$clean_utils" '."custom/colorpicker"."on-click" == "TEST_COLORPICKER_ON_CLICK"' "Custom colorpicker on-click override not compiled correctly into utilities.generated.jsonc"

waybar_test_assert_jq "$clean_utils" '."custom/vaults"."on-click" == "TEST_VAULTS_ON_CLICK"' "Custom vaults on-click override not compiled correctly into utilities.generated.jsonc"
waybar_test_assert_jq "$clean_utils" '."custom/vaults"."on-click-right" == "TEST_VAULTS_ON_CLICK_RIGHT"' "Custom vaults on-click-right override not compiled correctly into utilities.generated.jsonc"

waybar_test_assert_jq "$clean_utils" '."custom/touchpad"."on-click" == "TEST_TOUCHPAD_ON_CLICK"' "Custom touchpad on-click override not compiled correctly into utilities.generated.jsonc"
waybar_test_assert_jq "$clean_utils" '."custom/touchpad"."on-click-right" == "TEST_TOUCHPAD_ON_CLICK_RIGHT"' "Custom touchpad on-click-right override not compiled correctly into utilities.generated.jsonc"

waybar_test_assert_jq "$clean_utils" '."custom/streamdeck"."on-click" == "TEST_STREAMDECK_ON_CLICK"' "Custom streamdeck on-click override not compiled correctly into utilities.generated.jsonc"
waybar_test_assert_jq "$clean_utils" '."custom/streamdeck"."on-click-right" == "TEST_STREAMDECK_ON_CLICK_RIGHT"' "Custom streamdeck on-click-right override not compiled correctly into utilities.generated.jsonc"
waybar_test_assert_jq "$clean_utils" '."custom/streamdeck"."on-click-middle" == "TEST_STREAMDECK_ON_CLICK_MIDDLE"' "Custom streamdeck on-click-middle override not compiled correctly into utilities.generated.jsonc"
waybar_test_assert_jq "$clean_utils" '."custom/streamdeck".interval == 75' "Custom streamdeck interval override not compiled correctly into utilities.generated.jsonc"
waybar_test_assert_jq "$clean_utils" '."custom/streamdeck".signal == 97' "Custom streamdeck signal override not compiled correctly into utilities.generated.jsonc"

# Assert network custom configurations overrides compiled correctly (for i2pd/yggdrasil/ipfs)
clean_net_custom=$(waybar_test_read_jsonc "$TEST_DIR/modules/network-custom.generated.jsonc")
waybar_test_assert_jq "$clean_net_custom" '."custom/i2pd".interval == 74' "Custom i2pd interval override not compiled correctly into network-custom.generated.jsonc"
waybar_test_assert_jq "$clean_net_custom" '."custom/i2pd".signal == 96' "Custom i2pd signal override not compiled correctly into network-custom.generated.jsonc"
waybar_test_assert_jq "$clean_net_custom" '."custom/i2pd"."on-click" == "TEST_I2PD_ON_CLICK"' "Custom i2pd on-click override not compiled correctly into network-custom.generated.jsonc"
waybar_test_assert_jq "$clean_net_custom" '."custom/yggdrasil".interval == 73' "Custom yggdrasil interval override not compiled correctly"
waybar_test_assert_jq "$clean_net_custom" '."custom/yggdrasil".signal == 95' "Custom yggdrasil signal override not compiled correctly"
waybar_test_assert_jq "$clean_net_custom" '."custom/yggdrasil"."on-click" == "TEST_YGGDRASIL_ON_CLICK"' "Custom yggdrasil on-click override not compiled correctly"
waybar_test_assert_jq "$clean_net_custom" '."custom/ipfs".interval == 72' "Custom ipfs interval override not compiled correctly"
waybar_test_assert_jq "$clean_net_custom" '."custom/ipfs".signal == 94' "Custom ipfs signal override not compiled correctly"
waybar_test_assert_jq "$clean_net_custom" '."custom/ipfs"."on-click" == "TEST_IPFS_ON_CLICK"' "Custom ipfs on-click override not compiled correctly"

waybar_test_assert_jq "$clean_utils" '."custom/github"."on-click" | test("github.test/notifications")' "apps.github_notifications not wired into custom/github on-click"
waybar_test_assert_jq "$clean_utils" '."custom/github"."on-click-right" == "TEST_GITHUB_ON_CLICK_RIGHT"' "github.on_click_right override not compiled correctly"
waybar_test_assert_jq "$clean_utils" '."custom/github"."on-click-middle" == "TEST_GITHUB_ON_CLICK_MIDDLE"' "github.on_click_middle override not compiled correctly"
waybar_test_assert_jq "$clean_utils" '."custom/device-battery"."on-click" | test("TEST_SOLAAR")' "apps.solaar not wired into custom/device-battery on-click"
waybar_test_assert_jq "$clean_utils" '."custom/device-battery"."on-click-right" | test("app-open-key\\.sh input_settings")' "apps.input_settings not wired into custom/device-battery on-click-right via app-open-key.sh"
waybar_test_assert_jq "$clean_utils" '."custom/systemd"."on-click" | test("TEST_SYSTEMD_FAILED")' "apps.systemd_failed not wired into custom/systemd on-click"

echo "PASS: settings overrides (modules)"
waybar_test_end
