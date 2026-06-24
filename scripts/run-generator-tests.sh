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
cp modules/workspaces.jsonc "$TEST_DIR/modules/"
cp -r scripts "$TEST_DIR/scripts"

# Make sure the copied scripts are executable
chmod +x "$TEST_DIR"/scripts/*.sh "$TEST_DIR"/scripts/*.py

# 3. Export the custom WAYBAR_HOME environment variable to test behavior path independence
export WAYBAR_HOME="$TEST_DIR"
export WAYBAR_SCRIPTS="$TEST_DIR/scripts"

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

echo "Validating generated JSONC files..."

# Ensure we have generated files
generated_files=()
while IFS=  read -r -d $'\0'; do
    generated_files+=("$REPLY")
done < <(find "$TEST_DIR" -name "*.generated.jsonc" -print0)

if [ ${#generated_files[@]} -eq 0 ]; then
  echo "FAIL: No generated JSONC files were found!" >&2
  fail=1
fi

for file in "${generated_files[@]}"; do
  # Check if it parses as valid JSON
  if ! strip_jsonc "$file" 2>/dev/null; then
    echo "FAIL: JSON syntax error in $file" >&2
    fail=1
    continue
  fi

  # Run custom module configurations validation
  if ! validate_custom_module_configs "$file"; then
    fail=1
    continue
  fi

  # Check that it DOES NOT contain any hardcoded references to /home/ or ~/.config/waybar
  if grep -E "/home/|~/\.config/waybar" "$file" >/dev/null 2>&1; then
    echo "FAIL: Hardcoded path detected in $file" >&2
    grep -n -E "/home/|~/\.config/waybar" "$file" >&2
    fail=1
  fi
done

# 4b. Verify that all essential generated files exist and are not empty
echo "Checking essential generated files existence and size..."
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

for file_rel in "${essential_files[@]}"; do
  file_path="$TEST_DIR/$file_rel"
  if [ ! -f "$file_path" ]; then
    echo "FAIL: Expected generated file $file_rel was not found!" >&2
    fail=1
  elif [ ! -s "$file_path" ]; then
    echo "FAIL: Generated file $file_rel is empty!" >&2
    fail=1
  fi
done

# Check the generated CSS file too
css_file="$TEST_DIR/theme/workspaces.generated.css"
if [ ! -f "$css_file" ]; then
  echo "FAIL: workspaces.generated.css was not created!" >&2
  fail=1
else
  if grep -E "/home/|~/\.config/waybar" "$css_file" >/dev/null 2>&1; then
    echo "FAIL: Hardcoded path detected in $css_file" >&2
    fail=1
  fi
fi

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
    "unit": "F"
  },
  "active_window": {
    "zscroll": false,
    "max_length": 15
  },
  "audio": {
    "mpris_zscroll": false,
    "mpris_max_length": 20
  },
  "services": {
    "chkrootkit": {
      "service_name": "MOCK_CHKROOTKIT_SERVICE"
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
if ! "$TEST_DIR/scripts/generate-settings.sh" >/dev/null 2>&1; then
  echo "FAIL: generate-settings.sh failed with custom configuration" >&2
  exit 1
fi
if ! "$TEST_DIR/scripts/generate-module-configs.sh" >/dev/null 2>&1; then
  echo "FAIL: generate-module-configs.sh failed with custom configuration" >&2
  exit 1
fi

# Verify settings were compiled to JSON
if [ ! -f "$TEST_DIR/data/waybar-settings.json" ]; then
  echo "FAIL: waybar-settings.json was not compiled from waybar-settings.jsonc" >&2
  fail=1
fi

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
if ! echo "$clean_sys" | jq -e '."custom/chkrootkit"."on-click" | contains("MOCK_CHKROOTKIT_SERVICE")' >/dev/null 2>&1; then
  echo "FAIL: Overridden chkrootkit service name was not compiled correctly into system.generated.jsonc" >&2
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

if [ "$fail" -eq 0 ]; then
  echo "PASS: All generated configuration files are syntactically valid and free of hardcoded user paths."
else
  echo "FAIL: One or more validations failed!" >&2
  exit 1
fi

exit 0
