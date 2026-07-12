#!/usr/bin/env bash
# Generated-config validators for generator suites (sourced via waybar-test-harness.sh).

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

    def fail(msg):
        sys.stderr.write(f"FAIL: {sys.argv[1]} -> {msg}\n")
        sys.exit(1)

    def check_module_dict(data_dict):
        for key, val in data_dict.items():
            if key.startswith("custom/") and isinstance(val, dict):
                # Drawer handles are static icons. Waybar treats "tooltip" as a bool only:
                # - string tooltips are ignored (falls back to the glyph)
                # - JSON exec for static drawers previously broke tooltips entirely
                if key.endswith("-drawer"):
                    if "exec" in val:
                        fail(f"'{key}' must not use exec (static drawer; JSON exec broke tooltips)")
                    if val.get("return-type") == "json":
                        fail(f"'{key}' must not use return-type json")
                    if val.get("tooltip") is not True:
                        fail(f"'{key}' must set tooltip: true (bool), not a string or missing")
                    tip = val.get("tooltip-format")
                    if not isinstance(tip, str) or len(tip.strip()) < 3:
                        fail(f"'{key}' must set a descriptive tooltip-format string")
                    fmt = val.get("format")
                    if not isinstance(fmt, str):
                        fail(f"'{key}' must set format to a string (icon glyph)")
                    if fmt and tip == fmt:
                        fail(f"'{key}' tooltip-format must not be the icon glyph alone")
                    if "Click to expand" in tip:
                        fail(f"'{key}' tooltip-format must say 'Click to toggle' (not expand)")
                    if "Click to toggle" not in tip:
                        fail(f"'{key}' tooltip-format must include 'Click to toggle'")

                if "exec" in val:
                    if "tooltip" in val and isinstance(val["tooltip"], str):
                        fail(f"'{key}' has 'tooltip' set as a string (must be boolean for dynamic modules)")
                else:
                    if "tooltip" in val and not isinstance(val["tooltip"], (str, bool)):
                        fail(f"'{key}' has 'tooltip' set to an invalid type (must be string or boolean for static modules)")

                for action in ["exec", "on-click", "on-click-right", "on-click-middle", "on-scroll-up", "on-scroll-down"]:
                    if action in val and isinstance(val[action], str):
                        cmd = val[action]
                        if "$WAYBAR_HOME/scripts/" in cmd:
                            parts = cmd.split("$WAYBAR_HOME/scripts/")
                            if len(parts) > 1:
                                script_name = parts[1].split()[0].split(";")[0].split("&")[0].split("|")[0]
                                script_name = script_name.replace('"', '').replace("'", "")
                                script_path = os.path.join(waybar_home, "scripts", script_name)
                                if not os.path.isfile(script_path):
                                    fail(f"'{key}' references non-existent script '{script_path}' in '{action}'")

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

# shellcheck disable=SC2034  # consumed by validate_all_generated_files
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
  "modules/workspaces.generated.jsonc"
  "modules/dock-windows.generated.jsonc"
  "modules/groups-dock-windows.generated.jsonc"
  "modules/hypr-tools.generated.jsonc"
  "modules/utilities.generated.jsonc"
  "theme/tokens.generated.css"
  "theme/album-art.generated.css"
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
  while IFS= read -r -d $'\0'; do
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

    if ! validate_out=$(validate_custom_module_configs "$file" 2>&1); then
      echo "FAIL [$stage]: Custom module configuration validation failed for $file" >&2
      printf '%s\n' "$validate_out" >&2
      check_fail=1
      continue
    fi

    if grep -E "/home/|~/\.config/waybar" "$file" >/dev/null 2>&1; then
      echo "FAIL [$stage]: Hardcoded path detected in $file" >&2
      grep -n -E "/home/|~/\.config/waybar" "$file" >&2
      check_fail=1
    fi
    if grep -E 'scripts/' "$file" >/dev/null 2>&1 && ! grep -F '$WAYBAR_HOME' "$file" >/dev/null 2>&1; then
      echo "FAIL [$stage]: scripts/ path without \$WAYBAR_HOME in $file" >&2
      check_fail=1
    fi
    if grep -E '"(/tmp/|/var/tmp/)' "$file" >/dev/null 2>&1; then
      echo "FAIL [$stage]: absolute /tmp path in $file" >&2
      check_fail=1
    fi
  done

  return $check_fail
}
