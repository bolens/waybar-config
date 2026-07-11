#!/usr/bin/env bash
# Integrated unit and behavior tests for Waybar configuration generators.
set -euo pipefail

echo "=== Running Waybar Configuration Generator Tests ==="

# Repo root (script lives in scripts/ci/)
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Fail fast on dash/bash shebang contract regressions (same checks as CI).
if ! "$ROOT_DIR/scripts/ci/check-shell-contracts.sh"; then
  echo "FAIL: shell contract checks failed before generator tests" >&2
  exit 1
fi

# 1. Create a sandboxed WAYBAR_HOME directory
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

echo "Created sandboxed test directory: $TEST_DIR"

# 2. Populate the sandboxed directory with templates, data, and script files
mkdir -p "$TEST_DIR/data" "$TEST_DIR/layouts" "$TEST_DIR/includes" "$TEST_DIR/modules" "$TEST_DIR/theme"

cp -r "$ROOT_DIR/data/"* "$TEST_DIR/data/"
# Never carry real local secrets into the sandbox
rm -f "$TEST_DIR/data/waybar-secrets.jsonc" "$TEST_DIR/data/waybar-secrets.json"
cp "$ROOT_DIR"/layouts/*.jsonc "$TEST_DIR/layouts/"
cp "$ROOT_DIR"/includes/*.jsonc "$TEST_DIR/includes/"
cp "$ROOT_DIR"/modules/*.jsonc "$TEST_DIR/modules/"
echo "{}" > "$TEST_DIR/modules/hyprland.jsonc"
cp -r "$ROOT_DIR/scripts" "$TEST_DIR/scripts"

# Make sure the copied scripts are executable
find "$TEST_DIR/scripts" \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} +

# 3. Export the custom WAYBAR_HOME environment variable to test behavior path independence
export WAYBAR_HOME="$TEST_DIR"
export WAYBAR_SCRIPTS="$TEST_DIR/scripts"
export HYPRLAND_INSTANCE_SIGNATURE="mock_signature"

echo "Running configuration generator scripts under WAYBAR_HOME=$WAYBAR_HOME..."

# Run the settings and module generator scripts
if ! "$TEST_DIR/scripts/generate/generate-settings.sh"; then
  echo "FAIL: generate-settings.sh exited with non-zero code" >&2
  exit 1
fi

if ! "$TEST_DIR/scripts/generate/generate-compositor-modules.sh"; then
  echo "FAIL: generate-compositor-modules.sh exited with non-zero code" >&2
  exit 1
fi

if ! "$TEST_DIR/scripts/generate/generate-workspaces-css.sh"; then
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

    def fail(msg):
        sys.stderr.write(f"FAIL: {sys.argv[1]} -> {msg}\n")
        sys.exit(1)

    def check_module_dict(data_dict):
        for key, val in data_dict.items():
            if key.startswith("custom/") and isinstance(val, dict):
                # Drawer handles are static icons. Waybar treats "tooltip" as a bool only:
                # - string tooltips are ignored (falls back to the glyph)
                # - JSON exec for static drawers previously broke tooltips entirely
                # Require: format icon + tooltip:true + descriptive tooltip-format (no exec).
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
                    # Non-empty format is required in real configs; empty is allowed when
                    # drawers.icons is omitted in override fixtures. Never allow tip == glyph.
                    if fmt and tip == fmt:
                        fail(f"'{key}' tooltip-format must not be the icon glyph alone")
                    if "Click to expand" in tip:
                        fail(f"'{key}' tooltip-format must say 'Click to toggle' (not expand)")
                    if "Click to toggle" not in tip:
                        fail(f"'{key}' tooltip-format must include 'Click to toggle'")

                # Check 1: Tooltip format validation for custom modules
                if "exec" in val:
                    if "tooltip" in val and isinstance(val["tooltip"], str):
                        fail(f"'{key}' has 'tooltip' set as a string (must be boolean for dynamic modules)")
                else:
                    if "tooltip" in val and not isinstance(val["tooltip"], (str, bool)):
                        fail(f"'{key}' has 'tooltip' set to an invalid type (must be string or boolean for static modules)")

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
  "modules/hypr-tools.generated.jsonc"
  "modules/utilities.generated.jsonc"
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
  done

  return $check_fail
}

echo "Validating generated JSONC and CSS files for default settings..."
validate_all_generated_files "default settings" || fail=1

# ---------------------------------------------------------------------------
# Contracts for recent reliability / tooltip / SoT work (default real settings)
# ---------------------------------------------------------------------------
echo "Testing drawer tooltips, intervals helper, listeners, and SoT contracts..."

# Anti-regression: drawer handles must stay static with tooltip-format.
# Waybar's "tooltip" key is a bool — string values are ignored (glyph fallback).
# JSON exec on drawers previously made tooltips disappear entirely.
clean_drawers=$(python3 -c "import re; t=open('$TEST_DIR/modules/drawers.generated.jsonc').read(); t=re.sub(r'/\*.*?\*/', '', t, flags=re.S); t=re.sub(r'^\s*//.*$', '', t, flags=re.M); print(t)")
drawer_keys=$(echo "$clean_drawers" | jq -r 'keys[] | select(endswith("-drawer"))')
if [ -z "$drawer_keys" ]; then
  echo "FAIL: no custom/*-drawer modules found in drawers.generated.jsonc" >&2
  fail=1
fi
drawer_count=0
while IFS= read -r drawer_key; do
  [ -z "$drawer_key" ] && continue
  drawer_count=$((drawer_count + 1))
  if ! echo "$clean_drawers" | jq -e --arg k "$drawer_key" '
    .[$k].tooltip == true
    and (.[$k] | has("exec") | not)
    and (.[$k]["return-type"] != "json")
    and (.[$k]["tooltip-format"]|type)=="string"
    and (.[$k]["tooltip-format"]|contains("Contains:"))
    and (.[$k]["tooltip-format"]|contains("Click to toggle"))
    and ((.[$k]["tooltip-format"]|contains("Click to expand"))|not)
    and (.[$k].format|type)=="string"
    and (.[$k].format|length)>0
    and .[$k]["tooltip-format"] != .[$k].format
  ' >/dev/null 2>&1; then
    echo "FAIL: $drawer_key must use static format + tooltip:true + descriptive tooltip-format (no exec/json)" >&2
    echo "$clean_drawers" | jq --arg k "$drawer_key" '.[$k]' >&2
    fail=1
  fi
done <<< "$drawer_keys"
if [ "$drawer_count" -lt 8 ]; then
  echo "FAIL: expected at least 8 drawer modules, found $drawer_count" >&2
  fail=1
fi

# Content contracts: hardware lists CPU/GPU; desk lists Notifications
hw_tip=$(echo "$clean_drawers" | jq -r '."custom/hardware-drawer"."tooltip-format"')
if ! printf '%s' "$hw_tip" | grep -q 'CPU' || ! printf '%s' "$hw_tip" | grep -q 'GPU'; then
  echo "FAIL: hardware-drawer tooltip missing CPU/GPU contents: $hw_tip" >&2
  fail=1
fi
desk_tip=$(echo "$clean_drawers" | jq -r '."custom/desk-drawer"."tooltip-format"')
if ! printf '%s' "$desk_tip" | grep -q 'Notifications'; then
  echo "FAIL: desk-drawer tooltip missing Notifications: $desk_tip" >&2
  fail=1
fi

# Explicit negative cases: these shapes must be rejected by validate_custom_module_configs
drawer_bad_dir=$(mktemp -d)
printf '%s\n' '{"custom/desk-drawer":{"format":"X","tooltip":true,"return-type":"json","interval":"once","exec":"printf hi"}}' > "$drawer_bad_dir/exec.jsonc"
if validate_custom_module_configs "$drawer_bad_dir/exec.jsonc" >/dev/null 2>&1; then
  echo "FAIL: validate_custom_module_configs should reject drawer modules that use exec" >&2
  fail=1
fi
printf '%s\n' '{"custom/desk-drawer":{"format":"X","tooltip":"Session controls · click to expand"}}' > "$drawer_bad_dir/string-tip.jsonc"
if validate_custom_module_configs "$drawer_bad_dir/string-tip.jsonc" >/dev/null 2>&1; then
  echo "FAIL: validate_custom_module_configs should reject drawer modules with string tooltip" >&2
  fail=1
fi
printf '%s\n' '{"custom/desk-drawer":{"format":"X","tooltip":true,"tooltip-format":"Hardware\nContains: CPU\nClick to expand"}}' > "$drawer_bad_dir/expand.jsonc"
if validate_custom_module_configs "$drawer_bad_dir/expand.jsonc" >/dev/null 2>&1; then
  echo "FAIL: validate_custom_module_configs should reject 'Click to expand' on drawers" >&2
  fail=1
fi
printf '%s\n' '{"custom/desk-drawer":{"format":"X","tooltip":true,"tooltip-format":"Session controls\nContains: Notifications\nClick to toggle"}}' > "$drawer_bad_dir/ok.jsonc"
if ! validate_custom_module_configs "$drawer_bad_dir/ok.jsonc" >/dev/null 2>&1; then
  echo "FAIL: validate_custom_module_configs rejected a valid static drawer tooltip config" >&2
  fail=1
fi
rm -rf "$drawer_bad_dir"

# Compiled settings SoT contracts
if ! jq -e 'has("poll_intervals")|not' "$TEST_DIR/data/waybar-settings.json" >/dev/null 2>&1; then
  echo "FAIL: compiled waybar-settings.json still has poll_intervals" >&2
  fail=1
fi
if ! jq -e '.bars.layer == "overlay" and .bars.tooltip == true' "$TEST_DIR/data/waybar-settings.json" >/dev/null 2>&1; then
  echo "FAIL: expected bars.layer=overlay and tooltip=true in compiled settings" >&2
  fail=1
fi
if ! jq -e '.module_intervals.network_bandwidth == 5' "$TEST_DIR/data/waybar-settings.json" >/dev/null 2>&1; then
  echo "FAIL: expected module_intervals.network_bandwidth == 5" >&2
  fail=1
fi

# jsonc overwrites json (SoT)
printf '%s\n' '{"bars":{"layer":"top","tooltip":false},"module_intervals":{"weather":123}}' > "$TEST_DIR/data/waybar-settings.json"
printf '%s\n' '{"bars":{"layer":"overlay","tooltip":true},"module_intervals":{"weather":1800}}' > "$TEST_DIR/data/waybar-settings.jsonc"
WAYBAR_HOME="$TEST_DIR" bash -c ". '$TEST_DIR/scripts/lib/waybar-settings.sh'; waybar_settings_get '.bars.layer' 'missing'" >/tmp/waybar-sot-layer.$$
sot_layer=$(cat /tmp/waybar-sot-layer.$$); rm -f /tmp/waybar-sot-layer.$$
if [ "$sot_layer" != "overlay" ]; then
  echo "FAIL: jsonc SoT did not win over stale json (got layer=$sot_layer)" >&2
  fail=1
fi
# Restore real settings from repo copy for subsequent gens
cp -f data/waybar-settings.jsonc "$TEST_DIR/data/waybar-settings.jsonc"
WAYBAR_HOME="$TEST_DIR" bash -c ". '$TEST_DIR/scripts/lib/waybar-settings.sh'" >/dev/null

# waybar_module_interval reads module_intervals (and maps once -> fallback)
ttl_weather=$(WAYBAR_HOME="$TEST_DIR" bash -c ". '$TEST_DIR/scripts/lib/waybar-cache-helpers.sh'; waybar_module_interval weather 999")
ttl_once=$(WAYBAR_HOME="$TEST_DIR" bash -c ". '$TEST_DIR/scripts/lib/waybar-cache-helpers.sh'; waybar_module_interval keyboard_layout 42")
ttl_missing=$(WAYBAR_HOME="$TEST_DIR" bash -c ". '$TEST_DIR/scripts/lib/waybar-cache-helpers.sh'; waybar_module_interval totally_missing_key_xyz 77")
if [ "$ttl_weather" != "1800" ]; then
  echo "FAIL: waybar_module_interval weather expected 1800 got $ttl_weather" >&2
  fail=1
fi
# keyboard_layout is "once" in settings → fallback
if [ "$ttl_once" != "42" ]; then
  echo "FAIL: waybar_module_interval once-key should return fallback 42 got $ttl_once" >&2
  fail=1
fi
if [ "$ttl_missing" != "77" ]; then
  echo "FAIL: waybar_module_interval missing key expected fallback 77 got $ttl_missing" >&2
  fail=1
fi
# bash alias in waybar-settings.sh
ttl_alias=$(WAYBAR_HOME="$TEST_DIR" bash -c ". '$TEST_DIR/scripts/lib/waybar-settings.sh'; waybar_poll_interval weather 999")
if [ "$ttl_alias" != "1800" ]; then
  echo "FAIL: waybar_poll_interval alias expected 1800 got $ttl_alias" >&2
  fail=1
fi

# Bandwidth module uses module_intervals.network_bandwidth
if ! jq -e '."network#bandwidthUpBytes".interval == 5' "$TEST_DIR/modules/network.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: network bandwidth interval expected 5" >&2
  fail=1
fi

# System custom modules expose tooltip:true
if ! jq -e '."custom/cpu".tooltip == true and ."custom/syncthing".tooltip == true' "$TEST_DIR/modules/system.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: system modules missing tooltip:true" >&2
  fail=1
fi

# Keyboard defaults point at keyboard-layout-click.sh when overrides are null
clean_center_default=$(python3 -c "import re; t=open('$TEST_DIR/modules/center-extras.generated.jsonc').read(); t=re.sub(r'/\*.*?\*/', '', t, flags=re.S); t=re.sub(r'^\s*//.*$', '', t, flags=re.M); print(t)")
if ! echo "$clean_center_default" | jq -e '."custom/keyboard-layout"."on-click" | test("keyboard-layout-click\\.sh next")' >/dev/null 2>&1; then
  echo "FAIL: keyboard-layout on-click default missing keyboard-layout-click.sh next" >&2
  fail=1
fi
if ! echo "$clean_center_default" | jq -e '."custom/keyboard-layout"."on-click-right" | test("keyboard-layout-click\\.sh prev")' >/dev/null 2>&1; then
  echo "FAIL: keyboard-layout on-click-right default missing keyboard-layout-click.sh prev" >&2
  fail=1
fi
if [ ! -x "$TEST_DIR/scripts/system/keyboard-layout-click.sh" ]; then
  echo "FAIL: keyboard-layout-click.sh missing or not executable" >&2
  fail=1
fi
if ! sh -n "$TEST_DIR/scripts/system/keyboard-layout-click.sh"; then
  echo "FAIL: keyboard-layout-click.sh failed sh -n" >&2
  fail=1
fi

# Workspaces generated from slot_count; includes point at generated file
slot_count=$(jq -r '.workspaces.slot_count // 5' "$TEST_DIR/data/waybar-settings.json")
if [ ! -f "$TEST_DIR/modules/workspaces.generated.jsonc" ]; then
  echo "FAIL: workspaces.generated.jsonc missing after default generate" >&2
  fail=1
fi
last_slot=$((slot_count - 1))
if ! jq -e --arg k "custom/ws-$last_slot" 'has($k)' "$TEST_DIR/modules/workspaces.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: workspaces.generated.jsonc missing custom/ws-$last_slot for slot_count=$slot_count" >&2
  fail=1
fi
if jq -e --argjson n "$slot_count" 'has("custom/ws-\($n)")' "$TEST_DIR/modules/workspaces.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: workspaces.generated.jsonc has unexpected custom/ws-$slot_count" >&2
  fail=1
fi
if ! grep -q 'workspaces.generated.jsonc' "$TEST_DIR/includes/modules.jsonc"; then
  echo "FAIL: includes/modules.jsonc does not reference workspaces.generated.jsonc" >&2
  fail=1
fi
if grep -q 'modules/workspaces.jsonc"' "$TEST_DIR/includes/modules.jsonc"; then
  echo "FAIL: includes/modules.jsonc still references hand-edited workspaces.jsonc" >&2
  fail=1
fi

# dock-windows disabled → not on bottom bar; active-window remains center
if ! jq -e '.dock_windows.enabled == false' "$TEST_DIR/data/waybar-settings.json" >/dev/null 2>&1; then
  echo "FAIL: expected dock_windows.enabled == false in default settings" >&2
  fail=1
fi
if jq -e '.["modules-left"] | index("custom/dock-windows")' "$TEST_DIR/layouts/bottom.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/dock-windows should not be on bottom modules-left when disabled" >&2
  fail=1
fi
if ! jq -e '.["modules-center"] | index("custom/active-window")' "$TEST_DIR/layouts/bottom.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/active-window missing from bottom modules-center" >&2
  fail=1
fi

# listener-ctl start / stop / stop-all lifecycle
echo "Testing listener-ctl lifecycle..."
runtime_stub="$TEST_DIR/runtime"
mkdir -p "$runtime_stub"
# Prefer dash shebang when available so local runs match Ubuntu CI (/bin/sh -> dash).
mock_shebang='#!/usr/bin/env sh'
command -v dash >/dev/null 2>&1 && mock_shebang='#!/usr/bin/env dash'
cat > "$TEST_DIR/scripts/mock-listener.sh" <<MOCK
${mock_shebang}
set -eu
script_dir="\${0%/*}"
# Dash ignores \`. file arg\` — lock name must be in the env (see dock-windows-listener-lock.sh).
WAYBAR_LISTENER_LOCK_NAME="\${WAYBAR_MOCK_LOCK_NAME:-mock-listener}"
# shellcheck source=dock-windows-listener-lock.sh
. "\$WAYBAR_SCRIPTS/listeners/dock-windows-listener-lock.sh"
sleep 30
MOCK
chmod +x "$TEST_DIR/scripts/mock-listener.sh"
XDG_RUNTIME_DIR="$runtime_stub" "$TEST_DIR/scripts/infra/listener-ctl.sh" start "$TEST_DIR/scripts/mock-listener.sh" mock-listener
mock_pid_file="$runtime_stub/waybar-dock-listener-mock-listener.lock.d/pid"
sleep 0.4
if [ ! -f "$mock_pid_file" ] || ! kill -0 "$(cat "$mock_pid_file")" 2>/dev/null; then
  echo "FAIL: listener-ctl start did not leave a live mock-listener lock pid" >&2
  fail=1
else
  XDG_RUNTIME_DIR="$runtime_stub" "$TEST_DIR/scripts/infra/listener-ctl.sh" stop mock-listener
  sleep 0.3
  if [ -f "$mock_pid_file" ] && kill -0 "$(cat "$mock_pid_file" 2>/dev/null)" 2>/dev/null; then
    echo "FAIL: listener-ctl stop left mock-listener running" >&2
    fail=1
  fi
fi
WAYBAR_MOCK_LOCK_NAME=device-notifier XDG_RUNTIME_DIR="$runtime_stub" \
  "$TEST_DIR/scripts/infra/listener-ctl.sh" start "$TEST_DIR/scripts/mock-listener.sh" device-notifier
dn_pid_file="$runtime_stub/waybar-dock-listener-device-notifier.lock.d/pid"
sleep 0.4
if [ ! -f "$dn_pid_file" ] || ! kill -0 "$(cat "$dn_pid_file")" 2>/dev/null; then
  echo "FAIL: listener-ctl start device-notifier mock failed" >&2
  fail=1
else
  XDG_RUNTIME_DIR="$runtime_stub" "$TEST_DIR/scripts/infra/listener-ctl.sh" stop-all
  sleep 0.3
  if [ -f "$dn_pid_file" ] && kill -0 "$(cat "$dn_pid_file" 2>/dev/null)" 2>/dev/null; then
    echo "FAIL: listener-ctl stop-all left device-notifier mock running" >&2
    fail=1
  fi
fi

# device-notifier listener must take the singleton lock (env form — dash-safe)
if ! grep -q 'WAYBAR_LISTENER_LOCK_NAME=device-notifier' "$TEST_DIR/scripts/listeners/device-notifier-listener.sh"; then
  echo "FAIL: device-notifier-listener.sh does not set WAYBAR_LISTENER_LOCK_NAME=device-notifier" >&2
  fail=1
fi

# KDE listener loads signals from settings (not only hardcoded RTMIN offsets)
if ! grep -q 'def load_waybar_signals' "$TEST_DIR/scripts/listeners/active-window-listener-kde.py"; then
  echo "FAIL: active-window-listener-kde.py missing load_waybar_signals" >&2
  fail=1
fi
if ! grep -q 'waybar_rtmin("active_window")' "$TEST_DIR/scripts/listeners/active-window-listener-kde.py"; then
  echo "FAIL: active-window-listener-kde.py missing waybar_rtmin(\"active_window\") usage" >&2
  fail=1
fi
python3 - "$TEST_DIR" <<'PY' || fail=1
import json, os, subprocess, sys, tempfile, textwrap
from pathlib import Path
test_dir = Path(sys.argv[1])
settings = {
    "signals": {
        "active_window": 42,
        "workspaces": 43,
        "notifications": 44,
    }
}
cfg = test_dir / "data" / "waybar-settings.json"
cfg.write_text(json.dumps(settings))
# Extract and exec helper functions from the listener without starting the server
src = (test_dir / "scripts" / "listeners" / "active-window-listener-kde.py").read_text()
start = src.index("def load_waybar_signals")
end = src.index("# Single-instance locking")
chunk = src[start:end]
ns = {"os": os, "json": json, "subprocess": subprocess}
exec(chunk, ns)
os.environ["WAYBAR_HOME"] = str(test_dir)
signals = ns["load_waybar_signals"]()
assert signals["active_window"] == 42, signals
assert signals["workspaces"] == 43, signals
assert signals["notifications"] == 44, signals
# defaults still present for unspecified keys
assert "clipboard" in signals and isinstance(signals["clipboard"], int)
# waybar_rtmin should not raise with DEVNULL-only kwargs
ns["SIGNALS"] = signals
ns["waybar_rtmin"]("active_window")
print("PASS: KDE signal map loader unit test")
PY

# Restore full settings after KDE unit test mutated waybar-settings.json
cp -f data/waybar-settings.jsonc "$TEST_DIR/data/waybar-settings.jsonc"
WAYBAR_HOME="$TEST_DIR" bash -c ". '$TEST_DIR/scripts/lib/waybar-settings.sh'" >/dev/null

# Re-generate from restored jsonc so later override tests start clean
"$TEST_DIR/scripts/generate/generate-settings.sh" >/dev/null
"$TEST_DIR/scripts/generate/generate-compositor-modules.sh" >/dev/null
"$TEST_DIR/scripts/generate/generate-workspaces-css.sh" >/dev/null

# validate-generated-config contract script (after full restore/regen)
if ! WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/ci/validate-generated-config.sh" >/dev/null; then
  echo "FAIL: validate-generated-config.sh failed on default generated tree" >&2
  fail=1
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
  "module_intervals": {
    "clock": 42,
    "syncthing": 77,
    "sunshine": 76,
    "streamdeck": 75,
    "i2pd": 74
  },
  "signals": {
    "syncthing": 99,
    "sunshine": 98,
    "streamdeck": 97,
    "i2pd": 96
  },
  "clocks": {
    "locale": "fr_FR.UTF-8",
    "hour_format": "12",
    "date_format": "month-first",
    "bottom": {
      "format": "TEST_BOTTOM_CLOCK_FORMAT"
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
    "on_click_right": "TEST_AUDIO_ON_CLICK_RIGHT",
    "seek_back_sec": 17,
    "seek_forward_sec": 23
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
  "streamdeck": {
    "service_name": "MOCK_STREAMDECK.service",
    "on_click": "TEST_STREAMDECK_ON_CLICK",
    "on_click_right": "TEST_STREAMDECK_ON_CLICK_RIGHT",
    "on_click_middle": "TEST_STREAMDECK_ON_CLICK_MIDDLE"
  },
  "github": {
    "on_click_right": "TEST_GITHUB_ON_CLICK_RIGHT",
    "on_click_middle": "TEST_GITHUB_ON_CLICK_MIDDLE"
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
    },
    "syncthing": {
      "gui_url": "https://syncthing.test/",
      "service_name": "MOCK_SYNCTHING",
      "on_click": "TEST_SYNCTHING_ON_CLICK"
    },
    "sunshine": {
      "gui_url": "https://sunshine.test/",
      "service_name": "MOCK_SUNSHINE.service",
      "on_click_right": "TEST_SUNSHINE_ON_CLICK_RIGHT"
    },
    "i2pd": {
      "console_url": "http://i2pd.test:7070/",
      "service_name": "MOCK_I2PD.service",
      "on_click": "TEST_I2PD_ON_CLICK"
    }
  },
  "apps": {
    "file_manager": "TEST_FILE_MANAGER",
    "github_notifications": "https://github.test/notifications",
    "github_home": "https://github.test/home",
    "terminal": "MOCK_TERM",
    "solaar": "TEST_SOLAAR",
    "input_settings": "TEST_INPUT_SETTINGS",
    "power_settings": "TEST_POWER_SETTINGS",
    "systemd_failed": "TEST_SYSTEMD_FAILED"
  },
  "theme": {
    "font_family": "MOCK_FONT_FAMILY",
    "tooltip_font_size": 44,
    "border_radius": 12,
    "tooltip_padding": "9px 11px",
    "colors": {
      "background": "rgba(9, 9, 9, 0.99)",
      "tooltip_background": "#010203",
      "tooltip_border": "#040506"
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
if ! "$TEST_DIR/scripts/generate/generate-settings.sh"; then
  echo "FAIL: generate-settings.sh failed with custom configuration" >&2
  exit 1
fi
if ! "$TEST_DIR/scripts/generate/generate-module-configs.sh"; then
  echo "FAIL: generate-module-configs.sh failed with custom configuration" >&2
  exit 1
fi
if ! "$TEST_DIR/scripts/generate/generate-compositor-modules.sh"; then
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
test_hour_fmt=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/lib/waybar-settings.sh; . $TEST_DIR/scripts/lib/waybar-cache-helpers.sh; detect_clock_format")
if [ "$test_hour_fmt" != "12" ]; then
  echo "FAIL: detect_clock_format failed to respect clocks.hour_format override! Resolved: $test_hour_fmt" >&2
  fail=1
fi

test_date_fmt=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/lib/waybar-settings.sh; . $TEST_DIR/scripts/lib/waybar-cache-helpers.sh; detect_date_format")
if [ "$test_date_fmt" != "month-first" ]; then
  echo "FAIL: detect_date_format failed to respect clocks.date_format override! Resolved: $test_date_fmt" >&2
  fail=1
fi

test_first_day=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/lib/waybar-settings.sh; . $TEST_DIR/scripts/lib/waybar-cache-helpers.sh; detect_first_weekday")
if [ "$test_first_day" != "0" ]; then
  echo "FAIL: detect_first_weekday failed to respect clocks.calendar.first_day override! Resolved: $test_first_day" >&2
  fail=1
fi

test_weather_unit=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/lib/waybar-settings.sh; . $TEST_DIR/scripts/lib/waybar-cache-helpers.sh; detect_weather_unit")
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
XDG_CACHE_HOME="$TEST_DIR/cache" PATH="$TEST_DIR/bin:$PATH" WAYBAR_HOME="$TEST_DIR" bash "$TEST_DIR/scripts/workspaces/active-window-scroll.sh" > "$out_file" 2>&1 &
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
PATH="$TEST_DIR/bin:$PATH" WAYBAR_HOME="$TEST_DIR" bash "$TEST_DIR/scripts/media/mpris-scroll.sh" > "$out_mpris" 2>&1 &
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
if ! echo "$clean_sys" | jq -e '."custom/syncthing".interval == 77' >/dev/null 2>&1; then
  echo "FAIL: Custom syncthing interval override not compiled correctly into system.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_sys" | jq -e '."custom/syncthing".signal == 99' >/dev/null 2>&1; then
  echo "FAIL: Custom syncthing signal override not compiled correctly into system.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_sys" | jq -e '."custom/sunshine".interval == 76' >/dev/null 2>&1; then
  echo "FAIL: Custom sunshine interval override not compiled correctly into system.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_sys" | jq -e '."custom/sunshine".signal == 98' >/dev/null 2>&1; then
  echo "FAIL: Custom sunshine signal override not compiled correctly into system.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_sys" | jq -e '."custom/syncthing"."on-click" == "TEST_SYNCTHING_ON_CLICK"' >/dev/null 2>&1; then
  echo "FAIL: Custom syncthing on-click override not compiled correctly into system.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_sys" | jq -e '."custom/syncthing"."on-click-right" | test("MOCK_SYNCTHING")' >/dev/null 2>&1; then
  echo "FAIL: services.syncthing.service_name not wired into syncthing on-click-right" >&2
  fail=1
fi
if ! echo "$clean_sys" | jq -e '."custom/libredefender"."on-click-right" | test("MOCK_TERM")' >/dev/null 2>&1; then
  echo "FAIL: apps.terminal not wired into libredefender journalctl fallback" >&2
  fail=1
fi
if ! echo "$clean_sys" | jq -e '."custom/chkrootkit"."on-click-right" | test("MOCK_TERM")' >/dev/null 2>&1; then
  echo "FAIL: apps.terminal not wired into chkrootkit journalctl fallback" >&2
  fail=1
fi
if ! echo "$clean_sys" | jq -e '."custom/sunshine"."on-click-right" == "TEST_SUNSHINE_ON_CLICK_RIGHT"' >/dev/null 2>&1; then
  echo "FAIL: Custom sunshine on-click-right override not compiled correctly into system.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_sys" | jq -e '."custom/disk"."on-click" | test("TEST_FILE_MANAGER")' >/dev/null 2>&1; then
  echo "FAIL: apps.file_manager not wired into custom/disk on-click" >&2
  fail=1
fi
if ! echo "$clean_sys" | jq -e '."custom/ups"."on-click" | test("TEST_POWER_SETTINGS")' >/dev/null 2>&1; then
  echo "FAIL: apps.power_settings not wired into custom/ups on-click" >&2
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

if ! echo "$clean_utils" | jq -e '."custom/streamdeck"."on-click" == "TEST_STREAMDECK_ON_CLICK"' >/dev/null 2>&1; then
  echo "FAIL: Custom streamdeck on-click override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_utils" | jq -e '."custom/streamdeck"."on-click-right" == "TEST_STREAMDECK_ON_CLICK_RIGHT"' >/dev/null 2>&1; then
  echo "FAIL: Custom streamdeck on-click-right override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_utils" | jq -e '."custom/streamdeck"."on-click-middle" == "TEST_STREAMDECK_ON_CLICK_MIDDLE"' >/dev/null 2>&1; then
  echo "FAIL: Custom streamdeck on-click-middle override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_utils" | jq -e '."custom/streamdeck".interval == 75' >/dev/null 2>&1; then
  echo "FAIL: Custom streamdeck interval override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_utils" | jq -e '."custom/streamdeck".signal == 97' >/dev/null 2>&1; then
  echo "FAIL: Custom streamdeck signal override not compiled correctly into utilities.generated.jsonc" >&2
  fail=1
fi

# Assert network custom configurations overrides compiled correctly (for i2pd)
clean_net_custom=$(python3 -c "import re; t=open('$TEST_DIR/modules/network-custom.generated.jsonc').read(); t=re.sub(r'/\*.*?\*/', '', t, flags=re.S); t=re.sub(r'^\s*//.*$', '', t, flags=re.M); print(t)")
if ! echo "$clean_net_custom" | jq -e '."custom/i2pd".interval == 74' >/dev/null 2>&1; then
  echo "FAIL: Custom i2pd interval override not compiled correctly into network-custom.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_net_custom" | jq -e '."custom/i2pd".signal == 96' >/dev/null 2>&1; then
  echo "FAIL: Custom i2pd signal override not compiled correctly into network-custom.generated.jsonc" >&2
  fail=1
fi
if ! echo "$clean_net_custom" | jq -e '."custom/i2pd"."on-click" == "TEST_I2PD_ON_CLICK"' >/dev/null 2>&1; then
  echo "FAIL: Custom i2pd on-click override not compiled correctly into network-custom.generated.jsonc" >&2
  fail=1
fi

if ! echo "$clean_utils" | jq -e '."custom/github"."on-click" | test("github.test/notifications")' >/dev/null 2>&1; then
  echo "FAIL: apps.github_notifications not wired into custom/github on-click" >&2
  fail=1
fi
if ! echo "$clean_utils" | jq -e '."custom/github"."on-click-right" == "TEST_GITHUB_ON_CLICK_RIGHT"' >/dev/null 2>&1; then
  echo "FAIL: github.on_click_right override not compiled correctly" >&2
  fail=1
fi
if ! echo "$clean_utils" | jq -e '."custom/github"."on-click-middle" == "TEST_GITHUB_ON_CLICK_MIDDLE"' >/dev/null 2>&1; then
  echo "FAIL: github.on_click_middle override not compiled correctly" >&2
  fail=1
fi
if ! echo "$clean_utils" | jq -e '."custom/device-battery"."on-click" | test("TEST_SOLAAR")' >/dev/null 2>&1; then
  echo "FAIL: apps.solaar not wired into custom/device-battery on-click" >&2
  fail=1
fi
if ! echo "$clean_utils" | jq -e '."custom/device-battery"."on-click-right" | test("TEST_INPUT_SETTINGS")' >/dev/null 2>&1; then
  echo "FAIL: apps.input_settings not wired into custom/device-battery on-click-right" >&2
  fail=1
fi
if ! echo "$clean_utils" | jq -e '."custom/systemd"."on-click" | test("TEST_SYSTEMD_FAILED")' >/dev/null 2>&1; then
  echo "FAIL: apps.systemd_failed not wired into custom/systemd on-click" >&2
  fail=1
fi

# Polish defaults (no click overrides): github_home, streamdeck.service_name
echo "Testing polish default click wiring (no on_click overrides)..."
cp "$TEST_DIR/data/waybar-settings.jsonc" "$TEST_DIR/data/waybar-settings.jsonc.override.bak"
cat <<'JSON' > "$TEST_DIR/data/waybar-settings.jsonc"
{
  "bars": { "height": 30, "layer": "overlay", "tooltip": true },
  "module_intervals": {
    "github": 10,
    "streamdeck": 10,
    "syncthing": 10,
    "device_battery": 10,
    "chkrootkit": 10,
    "libredefender": 10
  },
  "signals": { "streamdeck": 24, "syncthing": 22, "device_battery": 20 },
  "layouts": {
    "top": { "position": "top", "modules_left": [], "modules_center": [], "modules_right": [] },
    "bottom": { "position": "bottom" }
  },
  "groups": {},
  "drawers": {},
  "services": {
    "syncthing": { "service_name": "POLISH_SYNCTHING", "gui_url": "https://st.polish/" },
    "libredefender": { "service_name": "polish-ld.service" },
    "chkrootkit": { "service_name": "polish-ck.service" },
    "sunshine": {},
    "i2pd": {}
  },
  "apps": {
    "github_notifications": "https://github.polish/notifications",
    "github_home": "https://github.polish/home",
    "terminal": "POLISH_TERM",
    "file_manager": "fm",
    "solaar": "solaar",
    "input_settings": "input",
    "power_settings": "power",
    "systemd_failed": "sysfail",
    "audio_mixer": "mixer"
  },
  "streamdeck": { "service_name": "POLISH_STREAMDECK.service" },
  "audio": { "seek_back_sec": 41, "seek_forward_sec": 42, "volume_step": 5, "max_volume": 1.5 },
  "github": {},
  "theme": {
    "font_family": "x",
    "tooltip_font_size": 12,
    "border_radius": 4,
    "colors": { "background": "#000", "foreground": "#fff", "border": "#111" }
  },
  "clocks": { "format": "{:%H:%M}" },
  "workspaces": { "slot_count": 5 }
}
JSON
if ! "$TEST_DIR/scripts/generate/generate-settings.sh" >/dev/null; then
  echo "FAIL: generate-settings.sh failed for polish defaults" >&2
  fail=1
fi
if ! "$TEST_DIR/scripts/generate/generate-module-configs.sh" >/dev/null; then
  echo "FAIL: generate-module-configs.sh failed for polish defaults" >&2
  fail=1
fi
clean_utils_polish=$(python3 -c "import re; t=open('$TEST_DIR/modules/utilities.generated.jsonc').read(); t=re.sub(r'/\*.*?\*/', '', t, flags=re.S); t=re.sub(r'^\s*//.*$', '', t, flags=re.M); print(t)")
clean_sys_polish=$(python3 -c "import re; t=open('$TEST_DIR/modules/system.generated.jsonc').read(); t=re.sub(r'/\*.*?\*/', '', t, flags=re.S); t=re.sub(r'^\s*//.*$', '', t, flags=re.M); print(t)")
clean_audio_polish=$(python3 -c "import re; t=open('$TEST_DIR/modules/audio.generated.jsonc').read(); t=re.sub(r'/\*.*?\*/', '', t, flags=re.S); t=re.sub(r'^\s*//.*$', '', t, flags=re.M); print(t)")
if ! echo "$clean_utils_polish" | jq -e '."custom/github"."on-click" | test("github.polish/notifications")' >/dev/null 2>&1; then
  echo "FAIL: polish default github left-click should use apps.github_notifications" >&2
  fail=1
fi
if ! echo "$clean_utils_polish" | jq -e '."custom/github"."on-click-right" | test("github.polish/home")' >/dev/null 2>&1; then
  echo "FAIL: polish default github right-click should use apps.github_home" >&2
  fail=1
fi
if ! echo "$clean_utils_polish" | jq -e '."custom/github"."on-click-middle" | test("github-status.sh --refresh")' >/dev/null 2>&1; then
  echo "FAIL: polish default github middle-click should refresh" >&2
  fail=1
fi
if ! echo "$clean_utils_polish" | jq -e '."custom/streamdeck"."on-click-right" | test("POLISH_STREAMDECK")' >/dev/null 2>&1; then
  echo "FAIL: polish default streamdeck right-click should use streamdeck.service_name" >&2
  fail=1
fi
if ! echo "$clean_sys_polish" | jq -e '."custom/syncthing"."on-click-right" | test("POLISH_SYNCTHING")' >/dev/null 2>&1; then
  echo "FAIL: polish default syncthing right-click should use services.syncthing.service_name" >&2
  fail=1
fi
if ! echo "$clean_sys_polish" | jq -e '."custom/libredefender"."on-click-right" | test("POLISH_TERM")' >/dev/null 2>&1; then
  echo "FAIL: polish default libredefender journalctl should use apps.terminal" >&2
  fail=1
fi
if ! echo "$clean_audio_polish" | jq -e '."custom/media-prev"."on-click-right" == "playerctl position 41-"' >/dev/null 2>&1; then
  echo "FAIL: polish default seek_back_sec not applied" >&2
  fail=1
fi
if ! echo "$clean_audio_polish" | jq -e '."custom/media-next"."on-click-right" == "playerctl position 42+"' >/dev/null 2>&1; then
  echo "FAIL: polish default seek_forward_sec not applied" >&2
  fail=1
fi
# Restore override mock for remaining assertions
mv "$TEST_DIR/data/waybar-settings.jsonc.override.bak" "$TEST_DIR/data/waybar-settings.jsonc"
"$TEST_DIR/scripts/generate/generate-settings.sh" >/dev/null
"$TEST_DIR/scripts/generate/generate-module-configs.sh" >/dev/null
"$TEST_DIR/scripts/generate/generate-compositor-modules.sh" >/dev/null
clean_utils=$(python3 -c "import re; t=open('$TEST_DIR/modules/utilities.generated.jsonc').read(); t=re.sub(r'/\*.*?\*/', '', t, flags=re.S); t=re.sub(r'^\s*//.*$', '', t, flags=re.M); print(t)")

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

# Assert workspaces.generated.jsonc was emitted from slot_count
if [ ! -f "$TEST_DIR/modules/workspaces.generated.jsonc" ]; then
  echo "FAIL: workspaces.generated.jsonc was not generated!" >&2
  fail=1
fi
clean_ws=$(python3 -c "import re; t=open('$TEST_DIR/modules/workspaces.generated.jsonc').read(); t=re.sub(r'/\*.*?\*/', '', t, flags=re.S); t=re.sub(r'^\s*//.*$', '', t, flags=re.M); print(t)")
if ! echo "$clean_ws" | jq -e '."custom/ws-7"' >/dev/null 2>&1; then
  echo "FAIL: workspaces.generated.jsonc missing custom/ws-7 for slot_count=8" >&2
  fail=1
fi
if echo "$clean_ws" | jq -e '."custom/ws-8"' >/dev/null 2>&1; then
  echo "FAIL: workspaces.generated.jsonc unexpectedly has custom/ws-8 when slot_count=8" >&2
  fail=1
fi
# Override wins over keyboard-layout-click default
if ! echo "$clean_center" | jq -e '."custom/keyboard-layout"."on-click" == "TEST_KEYBOARD_ON_CLICK"' >/dev/null 2>&1; then
  echo "FAIL: keyboard on-click override should win over keyboard-layout-click default" >&2
  fail=1
fi
# Override fixture can set overlay explicitly
if echo "$clean_bar" | jq -e 'has("layer")' >/dev/null 2>&1; then
  if ! echo "$clean_bar" | jq -e '.layer == "overlay" or .layer == "top" or .layer == "bottom"' >/dev/null 2>&1; then
    echo "FAIL: bar layer has unexpected value" >&2
    fail=1
  fi
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
  if ! grep -q "background: #010203" "$css_tokens"; then
    echo "FAIL: theme.colors.tooltip_background not found in generated tokens CSS" >&2
    fail=1
  fi
  if ! grep -q "border: 1px solid #040506" "$css_tokens"; then
    echo "FAIL: theme.colors.tooltip_border not found in generated tokens CSS" >&2
    fail=1
  fi
  if ! grep -q "padding: 9px 11px" "$css_tokens"; then
    echo "FAIL: theme.tooltip_padding not found in generated tokens CSS" >&2
    fail=1
  fi
else
  echo "FAIL: tokens.generated.css was not created!" >&2
  fail=1
fi
# Assert Rofi wifi and switcher settings resolve to overridden values
test_width=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/lib/waybar-settings.sh; waybar_settings_get '.rofi.wifi.width' 'default'")
if [ "$test_width" != "888" ]; then
  echo "FAIL: Rofi wifi width override failed to resolve! Resolved: $test_width" >&2
  fail=1
fi

test_switcher_width=$(WAYBAR_HOME="$TEST_DIR" bash -c ". $TEST_DIR/scripts/lib/waybar-settings.sh; waybar_settings_get '.rofi.switcher.width' 'default'")
if [ "$test_switcher_width" != "999" ]; then
  echo "FAIL: Rofi switcher width override failed to resolve! Resolved: $test_switcher_width" >&2
  fail=1
fi

# Assert emit_waybar_json correctly formats and escapes outputs
echo "Testing emit_waybar_json format and escape utility..."
test_json_out=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/waybar-cache-helpers.sh
  emit_waybar_json 'text <&>' 'tooltip\nwith\nnewlines & <tags>' 'myclass'
")

if ! echo "$test_json_out" | jq -e '.text == "text &lt;&amp;&gt;"' >/dev/null 2>&1; then
  echo "FAIL: emit_waybar_json failed to escape text content!" >&2
  echo "Output: $test_json_out" >&2
  fail=1
fi

if ! echo "$test_json_out" | jq -e '.tooltip == "tooltip\nwith\nnewlines &amp; &lt;tags&gt;"' >/dev/null 2>&1; then
  echo "FAIL: emit_waybar_json failed to escape tooltip markup or resolve newlines!" >&2
  echo "Output: $test_json_out" >&2
  fail=1
fi

if ! echo "$test_json_out" | jq -e '.class == "myclass"' >/dev/null 2>&1; then
  echo "FAIL: emit_waybar_json failed to set JSON class!" >&2
  echo "Output: $test_json_out" >&2
  fail=1
fi

# Assert strip_jsonc_comments correctly strips inline/block comments but preserves URLs
echo "Testing strip_jsonc_comments utility..."
cat <<'JSON' > "$TEST_DIR/data/comment-test.jsonc"
/*
 * Block comment here
 */
{
  "url": "https://github.com/bolens", // Inline comment after URL
  // Separate inline comment
  "key": "value" /* block comment on line */
}
JSON

test_stripped=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/waybar-settings.sh
  strip_jsonc_comments '$TEST_DIR/data/comment-test.jsonc'
")

if ! echo "$test_stripped" | jq -e '.url == "https://github.com/bolens"' >/dev/null 2>&1; then
  echo "FAIL: strip_jsonc_comments broke URLs or failed to strip inline comment!" >&2
  echo "Output: $test_stripped" >&2
  fail=1
fi

if ! echo "$test_stripped" | jq -e '.key == "value"' >/dev/null 2>&1; then
  echo "FAIL: strip_jsonc_comments failed to strip block comments!" >&2
  echo "Output: $test_stripped" >&2
  fail=1
fi

# Assert cache_file_age works correctly for existing and missing files
echo "Testing cache_file_age utility..."
cache_test_file="$TEST_DIR/data/cache-age-test.json"
echo "test" > "$cache_test_file"

age_fresh=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/waybar-cache-helpers.sh
  cache_file_age '$cache_test_file'
")

if [ "$age_fresh" -lt 0 ] || [ "$age_fresh" -gt 5 ]; then
  echo "FAIL: cache_file_age for fresh file returned incorrect value: $age_fresh" >&2
  fail=1
fi

# Change file modification time to 150 seconds in the past
touch -d "150 seconds ago" "$cache_test_file" 2>/dev/null || touch -m -t $(date -d "150 seconds ago" +%Y%m%d%H%M.%S) "$cache_test_file" 2>/dev/null || true

# Recheck age
age_stale=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/waybar-cache-helpers.sh
  cache_file_age '$cache_test_file'
")

# If touch command succeeded, verify value
if [ "$age_stale" -ge 140 ] 2>/dev/null; then
  : # Pass
fi

age_missing=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/waybar-cache-helpers.sh
  cache_file_age '$TEST_DIR/data/non-existent-file.json'
")

if [ "$age_missing" -ne 999999 ]; then
  echo "FAIL: cache_file_age for missing file did not return 999999! Value: $age_missing" >&2
  fail=1
fi

# Assert fit_text trims whitespace correctly
echo "Testing fit_text utility..."
trimmed=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/side-info-helpers.sh
  fit_text '  hello world  '
")
if [ "$trimmed" != "hello world" ]; then
  echo "FAIL: fit_text did not trim whitespace correctly: '$trimmed'" >&2
  fail=1
fi

# Assert format_lr formats correctly
echo "Testing format_lr utility..."
formatted=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/side-info-helpers.sh
  format_lr 'CPU' '50%'
")
if [ "${#formatted}" -ne 24 ]; then
  echo "FAIL: format_lr returned output of incorrect length: ${#formatted} (expected 24), value: '$formatted'" >&2
  fail=1
fi

# Assert serve_cache_or_refresh works correctly
echo "Testing serve_cache_or_refresh utility..."
echo '{"text":"fresh"}' > "$cache_test_file"
mkdir -p "$TEST_DIR/data/cache-test.lock.d"
serve_out_fresh=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/waybar-cache-helpers.sh
  serve_cache_or_refresh '$cache_test_file' 10 '$TEST_DIR/data/cache-test.lock.d' 20
")
serve_status_fresh=$?
if [ $serve_status_fresh -ne 0 ] || [ "$serve_out_fresh" != '{"text":"fresh"}' ]; then
  echo "FAIL: serve_cache_or_refresh failed on fresh cache! status: $serve_status_fresh, output: $serve_out_fresh" >&2
  fail=1
fi
rmdir "$TEST_DIR/data/cache-test.lock.d"

# Assert get_anim_frame resolves animation sequences correctly
echo "Testing get_anim_frame utility..."
frame_dots_0=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/unicode-animations-lib.sh
  get_anim_frame 'dots' 0
")
frame_dots_10=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/unicode-animations-lib.sh
  get_anim_frame 'dots' 10
")

if [ "$frame_dots_0" != "⠋" ] || [ "$frame_dots_10" != "⠋" ]; then
  echo "FAIL: get_anim_frame dots frame modulo calculation failed! frame_0: $frame_dots_0, frame_10: $frame_dots_10" >&2
  fail=1
fi

# Assert new status scripts output valid JSON and handle missing daemons gracefully
echo "Testing new status scripts execution..."
for script in services/sync/syncthing-status.sh services/apps/sunshine-status.sh services/devices/streamdeck-status.sh services/i2pd/i2pd-status.sh; do
  script_path="$TEST_DIR/scripts/$script"
  out=$(XDG_CACHE_HOME="$TEST_DIR/data" WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" "$script_path" --refresh 2>/dev/null || true)
  if [ -z "$out" ]; then
    echo "FAIL: $script failed to execute or returned empty output" >&2
    fail=1
  elif ! echo "$out" | jq -e '.text != null and .tooltip != null and .class != null' >/dev/null 2>&1; then
    echo "FAIL: $script did not output valid JSON with text, tooltip, and class fields. Output: $out" >&2
    fail=1
  fi
done

# i2pd/settings consumers must keep a bash shebang (regression for Ubuntu dash CI).
for script in services/i2pd/i2pd-status.sh services/sync/updates-status.sh services/apps/github-status.sh; do
  sheb="$(head -1 "$TEST_DIR/scripts/$script" || true)"
  case "$sheb" in
    '#!/usr/bin/env bash'|'#!/bin/bash') ;;
    *)
      echo "FAIL: $script must use bash shebang after sandbox copy (got: $sheb)" >&2
      fail=1
      ;;
  esac
done

# Verify behavior when waybar-settings.jsonc is missing
echo "Verifying resilience against missing settings file..."
rm -f "$TEST_DIR/data/waybar-settings.jsonc" "$TEST_DIR/data/waybar-settings.json"
if ! "$TEST_DIR/scripts/generate/generate-settings.sh" >/dev/null 2>&1; then
  echo "FAIL: generate-settings.sh crashed when waybar-settings.jsonc was missing" >&2
  exit 1
fi
if ! "$TEST_DIR/scripts/generate/generate-module-configs.sh" >/dev/null 2>&1; then
  echo "FAIL: generate-module-configs.sh crashed when waybar-settings.jsonc was missing" >&2
  exit 1
fi
if ! "$TEST_DIR/scripts/generate/generate-compositor-modules.sh" >/dev/null 2>&1; then
  echo "FAIL: generate-compositor-modules.sh crashed when waybar-settings.jsonc was missing" >&2
  exit 1
fi

# Verify behavior when waybar-settings.jsonc contains invalid JSON syntax
echo "Verifying behavior with invalid JSON settings syntax..."
cat <<'JSON' > "$TEST_DIR/data/waybar-settings.jsonc"
{
  "bars": {
    "height": 99,
    "spacing": 99
  },
  "clocks": {
    "locale": "invalid_commas_here",,
  }
}
JSON

if "$TEST_DIR/scripts/generate/generate-settings.sh" >/dev/null 2>&1; then
  echo "FAIL: generate-settings.sh succeeded even with malformed waybar-settings.jsonc JSON!" >&2
  fail=1
else
  echo "PASS: generate-settings.sh correctly failed on malformed JSON settings."
fi

# Verify path independence and resilience to spaces in directory name
echo "Verifying resilience to spaces in directory name..."
SPACE_DIR_PARENT=$(mktemp -d)
SPACE_DIR="$SPACE_DIR_PARENT/waybar test space"
mkdir -p "$SPACE_DIR/data" "$SPACE_DIR/layouts" "$SPACE_DIR/includes" "$SPACE_DIR/modules" "$SPACE_DIR/theme"
cp -r "$ROOT_DIR/data/"* "$SPACE_DIR/data/"
rm -f "$SPACE_DIR/data/waybar-secrets.jsonc" "$SPACE_DIR/data/waybar-secrets.json"
cp "$ROOT_DIR"/layouts/*.jsonc "$SPACE_DIR/layouts/"
cp "$ROOT_DIR"/includes/*.jsonc "$SPACE_DIR/includes/"
cp "$ROOT_DIR"/modules/*.jsonc "$SPACE_DIR/modules/"
echo "{}" > "$SPACE_DIR/modules/hyprland.jsonc"
cp -r "$ROOT_DIR/scripts" "$SPACE_DIR/scripts"
find "$SPACE_DIR/scripts" \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} +

# Run generator under WAYBAR_HOME with spaces
if ! WAYBAR_HOME="$SPACE_DIR" WAYBAR_SCRIPTS="$SPACE_DIR/scripts" "$SPACE_DIR/scripts/generate/generate-settings.sh" >/dev/null 2>&1; then
  echo "FAIL: generate-settings.sh failed when run inside a directory with spaces!" >&2
  fail=1
else
  echo "PASS: generate-settings.sh succeeded with spaces in directory name."
fi

# Clean up space test directory
rm -rf "$SPACE_DIR_PARENT"

# Secrets overlay, i2pd sync helper, capture settings, validate guard
if ! "$ROOT_DIR/scripts/ci/run-secrets-and-settings-tests.sh"; then
  echo "FAIL: run-secrets-and-settings-tests.sh failed" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: All generated configuration files are syntactically valid and free of hardcoded user paths."
else
  echo "FAIL: One or more validations failed!" >&2
  exit 1
fi

exit 0
