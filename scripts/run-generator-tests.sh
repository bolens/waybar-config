#!/usr/bin/env bash
# Integrated unit and behavior tests for Waybar configuration generators.
set -euo pipefail

echo "=== Running Waybar Configuration Generator Tests ==="

# 1. Create a sandboxed WAYBAR_HOME directory
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

echo "Created sandboxed test directory: $TEST_DIR"

# 2. Populate the sandboxed directory with templates, data, and script files
mkdir -p "$TEST_DIR/data" "$TEST_DIR/layouts" "$TEST_DIR/includes" "$TEST_DIR/modules" "$TEST_DIR/theme"

cp -r data/* "$TEST_DIR/data/"
cp layouts/*.jsonc "$TEST_DIR/layouts/"
cp includes/*.jsonc "$TEST_DIR/includes/"
cp modules/*.jsonc "$TEST_DIR/modules/"
echo "{}" > "$TEST_DIR/modules/hyprland.jsonc"
cp -r scripts "$TEST_DIR/scripts"

# Make sure the copied scripts are executable
chmod +x "$TEST_DIR"/scripts/*.sh "$TEST_DIR"/scripts/*.py

# 3. Export the custom WAYBAR_HOME environment variable to test behavior path independence
export WAYBAR_HOME="$TEST_DIR"
export WAYBAR_SCRIPTS="$TEST_DIR/scripts"
export HYPRLAND_INSTANCE_SIGNATURE="mock_signature"

echo "Running configuration generator scripts under WAYBAR_HOME=$WAYBAR_HOME..."

# Run the settings and module generator scripts
if ! "$TEST_DIR/scripts/generate-settings.sh"; then
  echo "FAIL: generate-settings.sh exited with non-zero code" >&2
  exit 1
fi

if ! "$TEST_DIR/scripts/generate-compositor-modules.sh"; then
  echo "FAIL: generate-compositor-modules.sh exited with non-zero code" >&2
  exit 1
fi

if ! "$TEST_DIR/scripts/generate-workspaces-css.sh"; then
  echo "FAIL: generate-workspaces-css.sh exited with non-zero code" >&2
  exit 1
fi

echo "Generator scripts completed successfully."

# 4. Run syntax and contents checks on the generated outputs
fail=0

strip_jsonc() {
  python3 - "$1" <<'PY'
import json, re, sys
try:
    text = open(sys.argv[1], encoding="utf-8").read()
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'^\s*//.*$', '', text, flags=re.M)
    json.loads(text)
except Exception as e:
    sys.stderr.write(f"JSON Parse Error: {e}\n")
    sys.exit(1)
PY
}

validate_custom_module_configs() {
  python3 - "$1" <<'PY'
import json, re, sys, os
try:
    text = open(sys.argv[1], encoding="utf-8").read()
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'^\s*//.*$', '', text, flags=re.M)
    data = json.loads(text)
    waybar_home = os.environ.get("WAYBAR_HOME", "")

    def check_module_dict(data_dict):
        for key, val in data_dict.items():
            if key.startswith("custom/") and isinstance(val, dict):
                # Check 1: Tooltip format validation for custom modules
                if "tooltip" in val and isinstance(val["tooltip"], str):
                    sys.stderr.write(f"FAIL: {sys.argv[1]} -> '{key}' has 'tooltip' set as a string (must be boolean)\n")
                    sys.exit(1)
                if "exec" not in val and "tooltip-format" in val:
                    if val.get("tooltip") is not True:
                        sys.stderr.write(f"FAIL: {sys.argv[1]} -> static '{key}' has 'tooltip-format' but 'tooltip' is not set to true\n")
                        sys.exit(1)
                
                # Check 2: Verify referenced script files exist
                for action in ["exec", "on-click", "on-click-right", "on-click-middle", "on-scroll-up", "on-scroll-down"]:
                    if action in val and isinstance(val[action], str):
                        cmd = val[action]
                        if "$WAYBAR_HOME/scripts/" in cmd:
                            parts = cmd.split("$WAYBAR_HOME/scripts/")
                            if len(parts) > 1:
                                # Split on common command arguments dividers/delimiters
                                script_name = parts[1].split()[0].split(";")[0].split("&")[0].split("|")[0]
                                script_name = script_name.replace('"', '').replace("'", "")
                                script_path = os.path.join(waybar_home, "scripts", script_name)
                                if not os.path.isfile(script_path):
                                    sys.stderr.write(f"FAIL: {sys.argv[1]} -> '{key}' references non-existent script '{script_path}' in '{action}'\n")
                                    sys.exit(1)

    if isinstance(data, dict):
        check_module_dict(data)
    elif isinstance(data, list):
        for item in data:
            if isinstance(item, dict):
                check_module_dict(item)
except Exception as e:
    sys.stderr.write(f"Validation failure in {sys.argv[1]}: {e}\n")
    sys.exit(1)
PY
}

essential_files=(
  "includes/bar-defaults.generated.jsonc"
  "layouts/top-shell.generated.jsonc"
  "layouts/bottom.generated.jsonc"
  "layouts/bottom-dock-left.generated.jsonc"
  "modules/groups.generated.jsonc"
  "modules/system.generated.jsonc"
  "modules/network.generated.jsonc"
  "modules/dock.generated.jsonc"
  "modules/groups-dock.generated.jsonc"
  "modules/center-extras.generated.jsonc"
  "modules/clock.generated.jsonc"
  "modules/audio.generated.jsonc"
  "modules/network-custom.generated.jsonc"
  "modules/drawers.generated.jsonc"
  "modules/dock-windows.generated.jsonc"
  "modules/hypr-tools.generated.jsonc"
  "theme/tokens.generated.css"
)

validate_all_generated_files() {
  local stage="$1"
  local check_fail=0

  for file_rel in "${essential_files[@]}"; do
    local file_path="$TEST_DIR/$file_rel"
    if [ ! -f "$file_path" ]; then
      echo "FAIL [$stage]: Expected generated file $file_rel was not found!" >&2
      check_fail=1
    elif [ ! -s "$file_path" ]; then
      echo "FAIL [$stage]: Generated file $file_rel is empty!" >&2
      check_fail=1
    elif [[ "$file_rel" == *.jsonc ]]; then
      if ! strip_jsonc "$file_path" 2>/dev/null; then
        echo "FAIL [$stage]: JSON syntax error in $file_rel" >&2
        check_fail=1
      fi
    fi
  done

  local css_file="$TEST_DIR/theme/workspaces.generated.css"
  if [ ! -f "$css_file" ]; then
    echo "FAIL [$stage]: workspaces.generated.css was not created!" >&2
    check_fail=1
  elif [ ! -s "$css_file" ]; then
    echo "FAIL [$stage]: workspaces.generated.css is empty!" >&2
    check_fail=1
  elif grep -E "/home/|~/\.config/waybar" "$css_file" >/dev/null 2>&1; then
    echo "FAIL [$stage]: Hardcoded path detected in $css_file" >&2
    check_fail=1
  fi

  local gen_files=()
  while IFS=  read -r -d $'\0'; do
      gen_files+=("$REPLY")
  done < <(find "$TEST_DIR" -name "*.generated.jsonc" -print0)

  if [ ${#gen_files[@]} -eq 0 ]; then
    echo "FAIL [$stage]: No generated JSONC files were found!" >&2
    check_fail=1
  fi

  for file in "${gen_files[@]}"; do
    if ! strip_jsonc "$file" 2>/dev/null; then
      echo "FAIL [$stage]: JSON syntax error in $file" >&2
      check_fail=1
      continue
    fi

    if ! validate_custom_module_configs "$file" >/dev/null 2>&1; then
      echo "FAIL [$stage]: Custom module configuration validation failed for $file" >&2
      check_fail=1
      continue
    fi

    if grep -E "/home/|~/\.config/waybar" "$file" >/dev/null 2>&1; then
      echo "FAIL [$stage]: Hardcoded path detected in $file" >&2
      grep -n -E "/home/|~/\.config/waybar" "$file" >&2
      check_fail=1
    fi
  done

  return $check_fail
}

echo "Validating generated JSONC and CSS files for default settings..."
validate_all_generated_files "default settings" || fail=1

# 5. Behavior and settings override tests
echo "Running behavioral tests for settings overrides..."

# Override settings file with a custom mock containing bars, services, clocks, and theme configurations
cat <<'JSON' > "$TEST_DIR/data/waybar-settings.jsonc"
{
  "bars": {
    "height": 99,
    "spacing": 99
  },
  "poll_intervals": {
    "clock": 42
  },
  "clocks": {
    "locale": "fr_FR.UTF-8",
    "hour_format": "12",
    "date_format": "month-first",
    "top": {
      "format": "TEST_TOP_CLOCK_FORMAT"
    },
    "calendar": {
      "first_day": 0
    }
  },
  "weather": {
    "unit": "F",
    "on_click": "TEST_WEATHER_ON_CLICK",
    "on_click_right": "TEST_WEATHER_ON_CLICK_RIGHT",
    "on_click_middle": "TEST_WEATHER_ON_CLICK_MIDDLE"
  },
  "active_window": {
    "zscroll": false,
    "max_length": 15
  },
  "audio": {
    "mpris_zscroll": false,
    "mpris_max_length": 20,
    "volume_step": 2,
    "max_volume": 1.2,
    "on_click": "TEST_AUDIO_ON_CLICK",
    "on_click_right": "TEST_AUDIO_ON_CLICK_RIGHT"
  },
  "bluetooth": {
    "on_click": "TEST_BLUETOOTH_ON_CLICK",
    "on_click_right": "TEST_BLUETOOTH_ON_CLICK_RIGHT",
    "on_click_middle": "TEST_BLUETOOTH_ON_CLICK_MIDDLE"
  },
  "keyboard": {
    "on_click": "TEST_KEYBOARD_ON_CLICK"
  },
  "gamemode": {
    "on_click": "TEST_GAMEMODE_ON_CLICK"
  },
  "kdeconnect": {
    "on_click": "TEST_KDECONNECT_ON_CLICK",
    "on_click_right": "TEST_KDECONNECT_ON_CLICK_RIGHT",
    "on_click_middle": "TEST_KDECONNECT_ON_CLICK_MIDDLE"
  },
  "device_notifier": {
    "on_click": "TEST_DEVICE_NOTIFIER_ON_CLICK",
    "on_click_right": "TEST_DEVICE_NOTIFIER_ON_CLICK_RIGHT"
  },
  "colorpicker": {
    "on_click": "TEST_COLORPICKER_ON_CLICK"
  },
  "vaults": {
    "on_click": "TEST_VAULTS_ON_CLICK",
    "on_click_right": "TEST_VAULTS_ON_CLICK_RIGHT"
  },
  "touchpad": {
    "on_click": "TEST_TOUCHPAD_ON_CLICK",
    "on_click_right": "TEST_TOUCHPAD_ON_CLICK_RIGHT"
  },
  "workspaces": {
    "slot_count": 8
  },
  "layouts": {
    "top": {
      "position": "top",
      "modules_left": ["group/desk-controls", "group/media"],
      "modules_center": ["group/desk-hypr", "custom/keybindhint", "custom/gamemode"],
      "modules_right": ["group/top-status", "group/power"]
    }
  },
  "services": {
    "chkrootkit": {
      "service_name": "MOCK_CHKROOTKIT_SERVICE",
      "on_click": "TEST_CHKROOTKIT_ON_CLICK"
    },
    "libredefender": {
      "service_name": "MOCK_LIBREDEFENDER_SERVICE",
      "on_click": "TEST_LIBREDEFENDER_ON_CLICK"
    }
  },
  "theme": {
    "font_family": "MOCK_FONT_FAMILY",
    "tooltip_font_size": 44,
    "border_radius": 12,
    "colors": {
      "background": "rgba(9, 9, 9, 0.99)"
    }
  },
  "rofi": {
    "wifi": {
      "width": 888,
      "lines": 33,
      "x_offset": -111,
      "y_offset": 11
    },
    "switcher": {
      "width": 999
    }
  }
}
JSON

# Run generators to build settings and rebuild modules
if ! "$TEST_DIR/scripts/generate-settings.sh"; then
  echo "FAIL: generate-settings.sh failed with custom configuration" >&2
  exit 1
fi
if ! "$TEST_DIR/scripts/generate-module-configs.sh"; then
  echo "FAIL: generate-module-configs.sh failed with custom configuration" >&2
  exit 1
fi
if ! "$TEST_DIR/scripts/generate-compositor-modules.sh"; then
  echo "FAIL: generate-compositor-modules.sh failed with custom configuration" >&2
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
  clean_clock=$(python3 -c "import re; t=open('$clock_conf').read(); t=re.sub(r'/\*.*?\*/', '', t, flags=re.S); t=re.sub(r'^\s*//.*$', '', t, flags=re.M); print(t)")
  if ! echo "$clean_clock" | jq -e '."clock#top".format == "TEST_TOP_CLOCK_FORMAT"' >/dev/null 2>&1; then
    echo "FAIL: Custom clock format not compiled correctly into clock.generated.jsonc" >&2
    echo "Generated output: $clean_clock" >&2
    fail=1
  fi
  if ! echo "$clean_clock" | jq -e '."clock#top".interval == 42' >/dev/null 2>&1; then
    echo "FAIL: Custom clock interval not compiled correctly into clock.generated.jsonc" >&2
    fail=1
  fi
  if ! echo "$clean_clock" | jq -e '."clock#bottom".format == "{:%a, %b %d %I:%M %p}"' >/dev/null 2>&1; then
    echo "FAIL: Bottom clock format did not compile default overridden by clocks.hour_format and date_format!" >&2
    fail=1
  fi
  if ! echo "$clean_clock" | jq -e '."clock#top".calendar.first_day == 0' >/dev/null 2>&1; then
    echo "FAIL: Calendar first day override was not compiled correctly into clock.generated.jsonc!" >&2
    fail=1
  fi
  if ! echo "$clean_clock" | jq -e '."clock#top".locale == "fr_FR.UTF-8"' >/dev/null 2>&1; then
    echo "FAIL: Clocks locale override fr_FR.UTF-8 not compiled correctly into clock.generated.jsonc!" >&2
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
  clean_audio=$(python3 -c "import re; t=open('$audio_conf').read(); t=re.sub(r'/\*.*?\*/', '', t, flags=re.S); t=re.sub(r'^\s*//.*$', '', t, flags=re.M); print(t)" 2>&1)
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
else
  echo "FAIL: audio.generated.jsonc was not generated!" >&2
  fail=1
fi

# Verify locale helpers respect overrides
test_hour_fmt=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/waybar-settings.sh; . $TEST_DIR/scripts/waybar-cache-helpers.sh; detect_clock_format")
if [ "$test_hour_fmt" != "12" ]; then
  echo "FAIL: detect_clock_format failed to respect clocks.hour_format override! Resolved: $test_hour_fmt" >&2
  fail=1
fi

test_date_fmt=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/waybar-settings.sh; . $TEST_DIR/scripts/waybar-cache-helpers.sh; detect_date_format")
if [ "$test_date_fmt" != "month-first" ]; then
  echo "FAIL: detect_date_format failed to respect clocks.date_format override! Resolved: $test_date_fmt" >&2
  fail=1
fi

test_first_day=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/waybar-settings.sh; . $TEST_DIR/scripts/waybar-cache-helpers.sh; detect_first_weekday")
if [ "$test_first_day" != "0" ]; then
  echo "FAIL: detect_first_weekday failed to respect clocks.calendar.first_day override! Resolved: $test_first_day" >&2
  fail=1
fi

test_weather_unit=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/waybar-settings.sh; . $TEST_DIR/scripts/waybar-cache-helpers.sh; detect_weather_unit")
if [ "$test_weather_unit" != "F" ]; then
  echo "FAIL: detect_weather_unit failed to respect weather.unit override! Resolved: $test_weather_unit" >&2
  fail=1
fi

# Verify active-window-scroll.sh works correctly without zscroll (using zscroll=false, max_length=15 override)
mkdir -p "$TEST_DIR/bin"
cat <<'SH' > "$TEST_DIR/bin/hyprctl"
#!/bin/sh
if [ "$1" = "activewindow" ]; then
  echo '{"title":"Very Long Window Title That Exceeds Fifteen Characters"}'
fi
SH
chmod +x "$TEST_DIR/bin/hyprctl"

out_file="$TEST_DIR/active-window-test.log"
XDG_CACHE_HOME="$TEST_DIR/cache" PATH="$TEST_DIR/bin:$PATH" WAYBAR_HOME="$TEST_DIR" bash "$TEST_DIR/scripts/active-window-scroll.sh" > "$out_file" 2>&1 &
sub_pid=$!

# Wait for directory creation and startup, then write test title to cache
sleep 0.3
mkdir -p "$TEST_DIR/cache/waybar"
echo "Very Long Window Title That Exceeds Fifteen Characters" > "$TEST_DIR/cache/waybar/active-window-title.raw"

sleep 0.6
kill "$sub_pid" 2>/dev/null || true

if ! grep -q '"text":"󰖲  Very Long Wi..."' "$out_file"; then
  echo "FAIL: active-window-scroll.sh failed to truncate correctly when zscroll is disabled!" >&2
  cat "$out_file" >&2
  fail=1
fi

# Verify mpris-scroll.sh works correctly without zscroll (using mpris_zscroll=false, mpris_max_length=20 override)
cat <<'SH' > "$TEST_DIR/bin/playerctl"
#!/bin/sh
if [ "$1" = "status" ]; then
  echo "Playing"
elif [ "$1" = "metadata" ]; then
  echo "󰝚 Heavy Metal Song Title That Exceeds Twenty Characters"
fi
SH
chmod +x "$TEST_DIR/bin/playerctl"

out_mpris="$TEST_DIR/mpris-test.log"
PATH="$TEST_DIR/bin:$PATH" WAYBAR_HOME="$TEST_DIR" bash "$TEST_DIR/scripts/mpris-scroll.sh" > "$out_mpris" 2>&1 &
mpris_pid=$!

sleep 0.8
kill "$mpris_pid" 2>/dev/null || true

if ! grep -q '󰝚 Heavy Metal Son...' "$out_mpris"; then
  echo "FAIL: mpris-scroll.sh failed to truncate correctly when zscroll is disabled!" >&2
  cat "$out_mpris" >&2
  fail=1
fi

# Assert bar configurations overrides compiled correctly
clean_bar=$(python3 -c "import re; t=open('$TEST_DIR/includes/bar-defaults.generated.jsonc').read(); t=re.sub(r'/\*.*?\*/', '', t, flags=re.S); t=re.sub(r'^\s*//.*$', '', t, flags=re.M); print(t)")
if ! echo "$clean_bar" | jq -e '.height == 99' >/dev/null 2>&1; then
  echo "FAIL: Overridden bar height was not compiled correctly into bar-defaults" >&2
  fail=1
fi
if ! echo "$clean_bar" | jq -e '.spacing == 99' >/dev/null 2>&1; then
  echo "FAIL: Overridden bar spacing was not compiled correctly into bar-defaults" >&2
  fail=1
fi

# Assert system services configuration overrides compiled correctly
clean_sys=$(python3 -c "import re; t=open('$TEST_DIR/modules/system.generated.jsonc').read(); t=re.sub(r'/\*.*?\*/', '', t, flags=re.S); t=re.sub(r'^\s*//.*$', '', t, flags=re.M); print(t)")
if ! echo "$clean_sys" | jq -e '."custom/chkrootkit"."on-click" == "TEST_CHKROOTKIT_ON_CLICK"' >/dev/null 2>&1; then
  echo "FAIL: Custom chkrootkit on-click override not compiled correctly into system.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_sys" | jq -e '."custom/libredefender"."on-click" == "TEST_LIBREDEFENDER_ON_CLICK"' >/dev/null 2>&1; then
  echo "FAIL: Custom libredefender on-click override not compiled correctly into system.generated.jsonc" >&2
  fail=1
fi

# Assert weather configurations click action overrides compiled correctly
clean_utils=$(python3 -c "import re; t=open('$TEST_DIR/modules/utilities.generated.jsonc').read(); t=re.sub(r'/\*.*?\*/', '', t, flags=re.S); t=re.sub(r'^\s*//.*$', '', t, flags=re.M); print(t)")
if ! echo "$clean_utils" | jq -e '."custom/weather"."on-click" == "TEST_WEATHER_ON_CLICK"' >/dev/null 2>&1; then
  echo "FAIL: Custom weather on-click override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_utils" | jq -e '."custom/weather"."on-click-right" == "TEST_WEATHER_ON_CLICK_RIGHT"' >/dev/null 2>&1; then
  echo "FAIL: Custom weather on-click-right override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_utils" | jq -e '."custom/weather"."on-click-middle" == "TEST_WEATHER_ON_CLICK_MIDDLE"' >/dev/null 2>&1; then
  echo "FAIL: Custom weather on-click-middle override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi

if ! echo "$clean_utils" | jq -e '."custom/kdeconnect"."on-click" == "TEST_KDECONNECT_ON_CLICK"' >/dev/null 2>&1; then
  echo "FAIL: Custom kdeconnect on-click override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_utils" | jq -e '."custom/kdeconnect"."on-click-right" == "TEST_KDECONNECT_ON_CLICK_RIGHT"' >/dev/null 2>&1; then
  echo "FAIL: Custom kdeconnect on-click-right override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_utils" | jq -e '."custom/kdeconnect"."on-click-middle" == "TEST_KDECONNECT_ON_CLICK_MIDDLE"' >/dev/null 2>&1; then
  echo "FAIL: Custom kdeconnect on-click-middle override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi

if ! echo "$clean_utils" | jq -e '."custom/device-notifier"."on-click" == "TEST_DEVICE_NOTIFIER_ON_CLICK"' >/dev/null 2>&1; then
  echo "FAIL: Custom device-notifier on-click override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_utils" | jq -e '."custom/device-notifier"."on-click-right" == "TEST_DEVICE_NOTIFIER_ON_CLICK_RIGHT"' >/dev/null 2>&1; then
  echo "FAIL: Custom device-notifier on-click-right override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi

if ! echo "$clean_utils" | jq -e '."custom/colorpicker"."on-click" == "TEST_COLORPICKER_ON_CLICK"' >/dev/null 2>&1; then
  echo "FAIL: Custom colorpicker on-click override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi

if ! echo "$clean_utils" | jq -e '."custom/vaults"."on-click" == "TEST_VAULTS_ON_CLICK"' >/dev/null 2>&1; then
  echo "FAIL: Custom vaults on-click override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_utils" | jq -e '."custom/vaults"."on-click-right" == "TEST_VAULTS_ON_CLICK_RIGHT"' >/dev/null 2>&1; then
  echo "FAIL: Custom vaults on-click-right override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi

if ! echo "$clean_utils" | jq -e '."custom/touchpad"."on-click" == "TEST_TOUCHPAD_ON_CLICK"' >/dev/null 2>&1; then
  echo "FAIL: Custom touchpad on-click override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_utils" | jq -e '."custom/touchpad"."on-click-right" == "TEST_TOUCHPAD_ON_CLICK_RIGHT"' >/dev/null 2>&1; then
  echo "FAIL: Custom touchpad on-click-right override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi

# Assert keyboard layout and gamemode configuration overrides compiled correctly
clean_center=$(python3 -c "import re; t=open('$TEST_DIR/modules/center-extras.generated.jsonc').read(); t=re.sub(r'/\*.*?\*/', '', t, flags=re.S); t=re.sub(r'^\s*//.*$', '', t, flags=re.M); print(t)")
if ! echo "$clean_center" | jq -e '."custom/keyboard-layout"."on-click" == "TEST_KEYBOARD_ON_CLICK"' >/dev/null 2>&1; then
  echo "FAIL: Custom keyboard on-click override not compiled correctly into center-extras.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_center" | jq -e '."custom/gamemode"."on-click" == "TEST_GAMEMODE_ON_CLICK"' >/dev/null 2>&1; then
  echo "FAIL: Custom gamemode on-click override not compiled correctly into center-extras.generated.jsonc" >&2
  fail=1
fi

# Assert layouts.top.modules_left override compiled correctly into top-left.generated.jsonc
clean_top_left=$(python3 -c "import re; t=open('$TEST_DIR/layouts/top-left.generated.jsonc').read(); t=re.sub(r'/\*.*?\*/', '', t, flags=re.S); t=re.sub(r'^\s*//.*$', '', t, flags=re.M); print(t)")
if ! echo "$clean_top_left" | jq -e '."modules-left" == ["group/desk-controls", "group/media"]' >/dev/null 2>&1; then
  echo "FAIL: Custom modules-left override not compiled correctly into top-left.generated.jsonc" >&2
  fail=1
fi

# Assert workspaces.slot_count override compiled correctly into groups-desk-hypr.generated.jsonc
clean_desk_hypr=$(python3 -c "import re; t=open('$TEST_DIR/modules/groups-desk-hypr.generated.jsonc').read(); t=re.sub(r'/\*.*?\*/', '', t, flags=re.S); t=re.sub(r'^\s*//.*$', '', t, flags=re.M); print(t)")
if ! echo "$clean_desk_hypr" | jq -e '."group/desk-hypr".modules | length == 11' >/dev/null 2>&1; then
  # 8 slots + 3 tail modules ("hyprland/submap", "custom/hyprlight", "custom/hyprwhspr") = 11 modules total
  echo "FAIL: Custom workspaces slot count override not compiled correctly into groups-desk-hypr.generated.jsonc" >&2
  fail=1
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
else
  echo "FAIL: tokens.generated.css was not created!" >&2
  fail=1
fi
# Assert Rofi wifi and switcher settings resolve to overridden values
test_width=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/waybar-settings.sh; waybar_settings_get '.rofi.wifi.width' 'default'")
if [ "$test_width" != "888" ]; then
  echo "FAIL: Rofi wifi width override failed to resolve! Resolved: $test_width" >&2
  fail=1
fi

test_switcher_width=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/waybar-settings.sh; waybar_settings_get '.rofi.switcher.width' 'default'")
if [ "$test_switcher_width" != "999" ]; then
  echo "FAIL: Rofi switcher width override failed to resolve! Resolved: $test_switcher_width" >&2
  fail=1
fi

# Verify behavior when waybar-settings.jsonc is missing
echo "Verifying resilience against missing settings file..."
rm -f "$TEST_DIR/data/waybar-settings.jsonc" "$TEST_DIR/data/waybar-settings.json"
if ! "$TEST_DIR/scripts/generate-settings.sh" >/dev/null 2>&1; then
  echo "FAIL: generate-settings.sh crashed when waybar-settings.jsonc was missing" >&2
  exit 1
fi
if ! "$TEST_DIR/scripts/generate-module-configs.sh" >/dev/null 2>&1; then
  echo "FAIL: generate-module-configs.sh crashed when waybar-settings.jsonc was missing" >&2
  exit 1
fi
if ! "$TEST_DIR/scripts/generate-compositor-modules.sh" >/dev/null 2>&1; then
  echo "FAIL: generate-compositor-modules.sh crashed when waybar-settings.jsonc was missing" >&2
  exit 1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: All generated configuration files are syntactically valid and free of hardcoded user paths."
else
  echo "FAIL: One or more validations failed!" >&2
  exit 1
fi

exit 0
