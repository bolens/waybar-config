#!/usr/bin/env bash
# Integrated unit and behavior tests for Waybar configuration generators.
set -euo pipefail

echo "=== Running Waybar Configuration Generator Tests ==="

# Repo root (script lives in scripts/ci/)
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Clear parent-shell fixture/override bleed before any sandbox work.
# Nested secrets suite also sanitizes again on entry.
# shellcheck source=waybar-test-sanitize-env.sh
. "$ROOT_DIR/scripts/ci/waybar-test-sanitize-env.sh"
waybar_test_sanitize_env

# Private runtime dir so $XDG_RUNTIME_DIR/waybar-compositor cannot leak from the host.
SUITE_RUNTIME=$(mktemp -d)
export XDG_RUNTIME_DIR="$SUITE_RUNTIME"
# Force Hyprland-shaped generated configs without exporting HYPRLAND_INSTANCE_SIGNATURE
# (that used to poison later detect_compositor / compositor-gate cases).
export WAYBAR_COMPOSITOR=hyprland

# Fail fast on dash/bash shebang contract regressions (same checks as CI).
if ! "$ROOT_DIR/scripts/ci/check-shell-contracts.sh"; then
  echo "FAIL: shell contract checks failed before generator tests" >&2
  exit 1
fi

# 1. Create a sandboxed WAYBAR_HOME directory
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR" "$SUITE_RUNTIME"' EXIT

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

echo "Validating generated JSONC and CSS files for default settings..."
validate_all_generated_files "default settings" || fail=1

# Positive portability: module configs must keep literal $WAYBAR_HOME (not expanded abs paths)
for port_file in \
  "$TEST_DIR/modules/system.generated.jsonc" \
  "$TEST_DIR/modules/utilities.generated.jsonc" \
  "$TEST_DIR/modules/audio.generated.jsonc"; do
  if [ ! -f "$port_file" ]; then
    echo "FAIL: missing $port_file after default generate" >&2
    fail=1
    continue
  fi
  if ! grep -Fq '$WAYBAR_HOME/scripts' "$port_file"; then
    echo "FAIL: $port_file missing literal \$WAYBAR_HOME/scripts" >&2
    fail=1
  fi
done
echo "PASS: generated modules keep literal \$WAYBAR_HOME/scripts"

# Makefile generate contract (dry-run must include the three entry scripts)
make_n=$(make -C "$ROOT_DIR" -n generate 2>/dev/null || true)
case "$make_n" in
  *generate-settings.sh*generate-compositor-modules.sh*generate-workspaces-css.sh*)
    echo "PASS: make generate dry-run lists settings+compositor+workspaces-css"
    ;;
  *)
    echo "FAIL: make -n generate missing expected scripts: $make_n" >&2
    fail=1
    ;;
esac

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

# waybar_module_interval reads module_intervals ("once" → long cache TTL)
ttl_weather=$(WAYBAR_HOME="$TEST_DIR" bash -c ". '$TEST_DIR/scripts/lib/waybar-cache-helpers.sh'; waybar_module_interval weather 999")
ttl_once=$(WAYBAR_HOME="$TEST_DIR" bash -c ". '$TEST_DIR/scripts/lib/waybar-cache-helpers.sh'; waybar_module_interval keyboard_layout 42")
ttl_missing=$(WAYBAR_HOME="$TEST_DIR" bash -c ". '$TEST_DIR/scripts/lib/waybar-cache-helpers.sh'; waybar_module_interval totally_missing_key_xyz 77")
if [ "$ttl_weather" != "1800" ]; then
  echo "FAIL: waybar_module_interval weather expected 1800 got $ttl_weather" >&2
  fail=1
fi
# keyboard_layout is "once" in settings → long TTL (not the short fallback)
if [ "$ttl_once" != "86400" ]; then
  echo "FAIL: waybar_module_interval once-key should return 86400 got $ttl_once" >&2
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
if ! echo "$clean_sys" | jq -e '."custom/disk"."on-click" | test("app-open-key\\.sh file_manager")' >/dev/null 2>&1; then
  echo "FAIL: apps.file_manager not wired into custom/disk on-click via app-open-key.sh" >&2
  fail=1
fi
if ! echo "$clean_sys" | jq -e '."custom/ups"."on-click" | test("app-open-key\\.sh power_settings")' >/dev/null 2>&1; then
  echo "FAIL: apps.power_settings not wired into custom/ups on-click via app-open-key.sh" >&2
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
if ! echo "$clean_utils" | jq -e '."custom/device-battery"."on-click-right" | test("app-open-key\\.sh input_settings")' >/dev/null 2>&1; then
  echo "FAIL: apps.input_settings not wired into custom/device-battery on-click-right via app-open-key.sh" >&2
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
touch -d "150 seconds ago" "$cache_test_file" 2>/dev/null \
  || touch -m -t "$(date -d "150 seconds ago" +%Y%m%d%H%M.%S)" "$cache_test_file" 2>/dev/null \
  || true

# Recheck age
age_stale=$(WAYBAR_HOME="$TEST_DIR" bash -c "
  . $TEST_DIR/scripts/lib/waybar-cache-helpers.sh
  cache_file_age '$cache_test_file'
")

# If touch command succeeded, verify value
if [ "$age_stale" -ge 140 ] 2>/dev/null; then
  : # Pass
elif [ "$age_stale" -ge 0 ] 2>/dev/null && [ "$age_stale" -lt 140 ] 2>/dev/null; then
  echo "FAIL: cache_file_age for stale file expected >=140, got $age_stale" >&2
  fail=1
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

# Hyprland without optional modules/hyprland.jsonc must still emit desk slots + hypr_tail
echo "Verifying Hyprland generate without modules/hyprland.jsonc..."
HYPR_DIR=$(mktemp -d)
mkdir -p "$HYPR_DIR/data" "$HYPR_DIR/layouts" "$HYPR_DIR/includes" "$HYPR_DIR/modules" "$HYPR_DIR/theme"
cp -r "$ROOT_DIR/data/"* "$HYPR_DIR/data/"
rm -f "$HYPR_DIR/data/waybar-secrets.jsonc" "$HYPR_DIR/data/waybar-secrets.json"
cp "$ROOT_DIR"/layouts/*.jsonc "$HYPR_DIR/layouts/" 2>/dev/null || true
cp "$ROOT_DIR"/includes/*.jsonc "$HYPR_DIR/includes/" 2>/dev/null || true
cp -r "$ROOT_DIR/scripts" "$HYPR_DIR/scripts"
find "$HYPR_DIR/scripts" \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} +
# Ensure settings compile exists for compositor generator
WAYBAR_HOME="$HYPR_DIR" WAYBAR_SCRIPTS="$HYPR_DIR/scripts" \
  "$HYPR_DIR/scripts/generate/generate-settings.sh" >/dev/null 2>&1 || true
rm -f "$HYPR_DIR/modules/hyprland.jsonc"
if ! HYPRLAND_INSTANCE_SIGNATURE=test-sig \
  WAYBAR_HOME="$HYPR_DIR" WAYBAR_SCRIPTS="$HYPR_DIR/scripts" \
  "$HYPR_DIR/scripts/generate/generate-compositor-modules.sh" >/dev/null 2>&1; then
  echo "FAIL: generate-compositor-modules.sh failed on Hyprland without hyprland.jsonc" >&2
  fail=1
else
  hypr_mods=$(python3 -c "
import json, re
t=open('$HYPR_DIR/modules/groups-desk-hypr.generated.jsonc').read()
t=re.sub(r'/\*.*?\*/', '', t, flags=re.S)
t=re.sub(r'^\s*//.*$', '', t, flags=re.M)
print(','.join(json.loads(t)['group/desk-hypr']['modules']))
")
  case "$hypr_mods" in
    *custom/ws-0*hyprland/submap*custom/hyprlight*custom/hyprwhspr*)
      echo "PASS: Hyprland desk group keeps slots + hypr_tail without hyprland.jsonc"
      ;;
    *)
      echo "FAIL: Hyprland desk group missing slots/tail without hyprland.jsonc: $hypr_mods" >&2
      fail=1
      ;;
  esac
fi
rm -rf "$HYPR_DIR"

# liquidctl module: generator wiring + status script behavior (fixture CLI)
echo "Testing liquidctl module wiring and status script..."
# Restore SoT settings (prior override tests replace waybar-settings.jsonc) and regenerate.
cp "$ROOT_DIR/data/waybar-settings.jsonc" "$TEST_DIR/data/waybar-settings.jsonc"
if ! "$TEST_DIR/scripts/generate/generate-settings.sh"; then
  echo "FAIL: generate-settings.sh failed before liquidctl checks" >&2
  fail=1
fi
if ! jq -e '."custom/liquidctl".exec | test("system/liquidctl-status\\.sh$")' "$TEST_DIR/modules/system.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/liquidctl exec missing system/liquidctl-status.sh" >&2
  fail=1
fi
if ! jq -e '."custom/liquidctl".interval == 60' "$TEST_DIR/modules/system.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/liquidctl interval expected 60 from module_intervals.liquidctl" >&2
  fail=1
fi
if ! jq -e '."custom/liquidctl"."on-click-middle" | test("liquidctl-status\\.sh --refresh")' "$TEST_DIR/modules/system.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/liquidctl middle-click should refresh" >&2
  fail=1
fi
if ! jq -e '.["group/hardware"].modules | index("custom/liquidctl")' "$TEST_DIR/modules/groups.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/liquidctl missing from group/hardware modules" >&2
  fail=1
fi
if ! jq -e '.module_intervals.liquidctl == 60' "$TEST_DIR/data/waybar-settings.json" >/dev/null 2>&1; then
  echo "FAIL: module_intervals.liquidctl expected 60 in compiled settings" >&2
  fail=1
fi
if ! jq -e '.thresholds.liquidctl.temp.warning == 55 and .thresholds.liquidctl.temp.critical == 65' "$TEST_DIR/data/waybar-settings.json" >/dev/null 2>&1; then
  echo "FAIL: thresholds.liquidctl.temp missing/wrong in compiled settings" >&2
  fail=1
fi
if ! jq -e '.liquidctl.skip_corsair_psu_if_hwmon == true' "$TEST_DIR/data/waybar-settings.json" >/dev/null 2>&1; then
  echo "FAIL: liquidctl.skip_corsair_psu_if_hwmon expected true in compiled settings" >&2
  fail=1
fi
if [ ! -x "$TEST_DIR/scripts/system/liquidctl-status.sh" ]; then
  echo "FAIL: liquidctl-status.sh missing or not executable" >&2
  fail=1
fi
if ! bash -n "$TEST_DIR/scripts/system/liquidctl-status.sh"; then
  echo "FAIL: liquidctl-status.sh failed bash -n" >&2
  fail=1
fi

LIQUID_FAKE=$(mktemp -d)
cat >"$LIQUID_FAKE/liquidctl" <<'EOF'
#!/usr/bin/env bash
# Fixture: AIO + RGB-only device (RGB should be ignored)
cat <<'JSON'
[
  {
    "description": "NZXT Kraken X63",
    "bus": "hid",
    "address": "/dev/hidraw0",
    "status": [
      {"key": "Liquid temperature", "value": 56.5, "unit": "°C"},
      {"key": "Fan speed", "value": 1200.0, "unit": "rpm"},
      {"key": "Pump speed", "value": 2150.0, "unit": "rpm"}
    ]
  },
  {
    "description": "ASUS Aura LED Controller",
    "bus": "hid",
    "address": "/dev/hidraw1",
    "status": [
      {"key": "ARGB channels", "value": 3, "unit": ""},
      {"key": "RGB channels", "value": 1, "unit": ""}
    ]
  }
]
JSON
EOF
chmod +x "$LIQUID_FAKE/liquidctl"
LIQUID_CACHE=$(mktemp -d)
liquid_out=$(
  XDG_CACHE_HOME="$LIQUID_CACHE" \
  WAYBAR_HOME="$TEST_DIR" \
  WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_LIQUIDCTL_BIN="$LIQUID_FAKE/liquidctl" \
  WAYBAR_CORSAIRPSU_PRESENT=0 \
  "$TEST_DIR/scripts/system/liquidctl-status.sh" --refresh
) || true
if ! printf '%s' "$liquid_out" | jq -e '.class == "warning"' >/dev/null 2>&1; then
  echo "FAIL: liquidctl-status expected warning class at 56.5°C (warn=55): $liquid_out" >&2
  fail=1
fi
if ! printf '%s' "$liquid_out" | jq -e '.text | test("󰖌")' >/dev/null 2>&1; then
  echo "FAIL: liquidctl-status text missing liquidctl icon: $liquid_out" >&2
  fail=1
fi
if ! printf '%s' "$liquid_out" | jq -e '.tooltip | test("Kraken") and (test("ASUS Aura LED Controller") | not)' >/dev/null 2>&1; then
  echo "FAIL: liquidctl tooltip should include Kraken and skip Aura-only: $liquid_out" >&2
  fail=1
fi
# Aura devices may be noted as skipped (OpenRGB/ckb), but must not appear as telemetry blocks
if ! printf '%s' "$liquid_out" | jq -e '.tooltip | test("Skipped .*Aura")' >/dev/null 2>&1; then
  echo "FAIL: liquidctl tooltip should note skipped Aura RGB devices: $liquid_out" >&2
  fail=1
fi
# Missing binary → disconnected (empty text)
liquid_missing=$(
  XDG_CACHE_HOME="$LIQUID_CACHE" \
  WAYBAR_HOME="$TEST_DIR" \
  WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_LIQUIDCTL_BIN="$LIQUID_FAKE/no-such-liquidctl" \
  PATH="/usr/bin:/bin" \
  "$TEST_DIR/scripts/system/liquidctl-status.sh" --refresh
) || true
if ! printf '%s' "$liquid_missing" | jq -e '.class == "disconnected" and .text == ""' >/dev/null 2>&1; then
  echo "FAIL: liquidctl missing binary should emit disconnected: $liquid_missing" >&2
  fail=1
fi
# Empty status JSON → disconnected
cat >"$LIQUID_FAKE/liquidctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '[]'
EOF
chmod +x "$LIQUID_FAKE/liquidctl"
liquid_empty=$(
  XDG_CACHE_HOME="$LIQUID_CACHE" \
  WAYBAR_HOME="$TEST_DIR" \
  WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_LIQUIDCTL_BIN="$LIQUID_FAKE/liquidctl" \
  "$TEST_DIR/scripts/system/liquidctl-status.sh" --refresh
) || true
if ! printf '%s' "$liquid_empty" | jq -e '.class == "disconnected"' >/dev/null 2>&1; then
  echo "FAIL: liquidctl empty status should emit disconnected: $liquid_empty" >&2
  fail=1
fi
rm -rf "$LIQUID_FAKE" "$LIQUID_CACHE"

# Aura-only → disconnect (prefer OpenRGB); no status HID probe needed beyond list
LIQUID_FAKE=$(mktemp -d)
LIQUID_CACHE=$(mktemp -d)
LIQUID_LOG="$LIQUID_FAKE/calls.log"
: >"$LIQUID_LOG"
cat >"$LIQUID_FAKE/liquidctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$LIQUID_LOG"
args=("\$@")
has_json=0; has_list=0; has_status=0; i=0
while [ \$i -lt \${#args[@]} ]; do
  case "\${args[\$i]}" in --json) has_json=1;; list) has_list=1;; status) has_status=1;; esac
  i=\$((i + 1))
done
if [ "\$has_list" -eq 1 ] && [ "\$has_json" -eq 1 ]; then
  echo '[{"description":"ASUS Aura LED Controller","driver":"AuraLed"}]'
  exit 0
fi
# status must not be required for Aura-only hide path
exit 1
EOF
chmod +x "$LIQUID_FAKE/liquidctl"
liquid_aura=$(
  XDG_CACHE_HOME="$LIQUID_CACHE" \
  WAYBAR_HOME="$TEST_DIR" \
  WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_LIQUIDCTL_BIN="$LIQUID_FAKE/liquidctl" \
  WAYBAR_CORSAIRPSU_PRESENT=0 \
  "$TEST_DIR/scripts/system/liquidctl-status.sh" --refresh
) || true
if ! printf '%s' "$liquid_aura" | jq -e '.class == "disconnected" and (.tooltip | test("Aura|OpenRGB"; "i"))' >/dev/null 2>&1; then
  echo "FAIL: liquidctl Aura-only should disconnect: $liquid_aura" >&2
  fail=1
fi
if grep -q 'status' "$LIQUID_LOG" 2>/dev/null; then
  echo "FAIL: liquidctl Aura-only must not call status (HID). Log:" >&2
  cat "$LIQUID_LOG" >&2 || true
  fail=1
fi
rm -rf "$LIQUID_FAKE" "$LIQUID_CACHE"

# Partial failure: bulk --json suppressed (Aura error), per-device --pick still works
# when Corsair PSU is NOT covered by corsairpsu hwmon.
LIQUID_FAKE=$(mktemp -d)
LIQUID_CACHE=$(mktemp -d)
LIQUID_LOG="$LIQUID_FAKE/calls.log"
: >"$LIQUID_LOG"
cat >"$LIQUID_FAKE/liquidctl" <<EOF
#!/usr/bin/env bash
# Mimic liquidctl: bulk status --json fails when any device errors; per-pick works.
printf '%s\n' "\$*" >>"$LIQUID_LOG"
args=("\$@")
has_json=0
has_list=0
has_status=0
pick=""
i=0
while [ \$i -lt \${#args[@]} ]; do
  case "\${args[\$i]}" in
    --json) has_json=1 ;;
    list) has_list=1 ;;
    status) has_status=1 ;;
    --pick)
      i=\$((i + 1))
      pick="\${args[\$i]:-}"
      ;;
  esac
  i=\$((i + 1))
done
if [ "\$has_list" -eq 1 ] && [ "\$has_json" -eq 1 ]; then
  cat <<'JSON'
[
  {"description":"Corsair HX1500i","driver":"CorsairHidPsu"},
  {"description":"ASUS Aura LED Controller","driver":"AuraLed"}
]
JSON
  exit 0
fi
if [ "\$has_status" -eq 1 ] && [ "\$has_json" -eq 1 ]; then
  if [ -z "\$pick" ]; then
    # Bulk call: Aura would error → liquidctl prints no JSON
    exit 1
  fi
  if [ "\$pick" = "0" ]; then
    cat <<'JSON'
[{"description":"Corsair HX1500i","status":[
  {"key":"VRM temperature","value":51.2,"unit":"°C"},
  {"key":"Total power output","value":154.0,"unit":"W"}
]}]
JSON
    exit 0
  fi
  exit 1
fi
exit 1
EOF
chmod +x "$LIQUID_FAKE/liquidctl"
liquid_partial=$(
  XDG_CACHE_HOME="$LIQUID_CACHE" \
  WAYBAR_HOME="$TEST_DIR" \
  WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_LIQUIDCTL_BIN="$LIQUID_FAKE/liquidctl" \
  WAYBAR_CORSAIRPSU_PRESENT=0 \
  "$TEST_DIR/scripts/system/liquidctl-status.sh" --refresh
) || true
if ! printf '%s' "$liquid_partial" | jq -e '.class == "normal" and (.tooltip | test("HX1500i")) and (.text | test("󰖌"))' >/dev/null 2>&1; then
  echo "FAIL: liquidctl partial-failure fallback should show HX telemetry: $liquid_partial" >&2
  fail=1
fi
# With skips present, must use --pick (not rely on bulk status succeeding)
if ! grep -qE 'status.*--pick|--pick.*' "$LIQUID_LOG" 2>/dev/null; then
  echo "FAIL: liquidctl should probe keepers with --pick when skips apply. Log:" >&2
  cat "$LIQUID_LOG" >&2 || true
  fail=1
fi
# When corsairpsu hwmon covers PSU, liquidctl should hide (no exclusive devices) and never status
: >"$LIQUID_LOG"
liquid_skip_psu=$(
  XDG_CACHE_HOME="$LIQUID_CACHE" \
  WAYBAR_HOME="$TEST_DIR" \
  WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_LIQUIDCTL_BIN="$LIQUID_FAKE/liquidctl" \
  WAYBAR_CORSAIRPSU_PRESENT=1 \
  "$TEST_DIR/scripts/system/liquidctl-status.sh" --refresh
) || true
if ! printf '%s' "$liquid_skip_psu" | jq -e '.class == "disconnected" and (.tooltip | test("corsairpsu|PSU covered|hwmon"; "i"))' >/dev/null 2>&1; then
  echo "FAIL: liquidctl should disconnect when PSU covered by corsairpsu: $liquid_skip_psu" >&2
  fail=1
fi
if grep -q 'status' "$LIQUID_LOG" 2>/dev/null; then
  echo "FAIL: liquidctl must not call status when PSU+Aura covered. Log:" >&2
  cat "$LIQUID_LOG" >&2 || true
  fail=1
fi
# hwmon tree detection (WAYBAR_HWMON_ROOT) also triggers skip
HWMON_TREE="$LIQUID_FAKE/hwmon"
mkdir -p "$HWMON_TREE/hwmon0"
echo corsairpsu >"$HWMON_TREE/hwmon0/name"
: >"$LIQUID_LOG"
liquid_hwmon=$(
  XDG_CACHE_HOME="$LIQUID_CACHE" \
  WAYBAR_HOME="$TEST_DIR" \
  WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_LIQUIDCTL_BIN="$LIQUID_FAKE/liquidctl" \
  WAYBAR_HWMON_ROOT="$HWMON_TREE" \
  "$TEST_DIR/scripts/system/liquidctl-status.sh" --refresh
) || true
if ! printf '%s' "$liquid_hwmon" | jq -e '.class == "disconnected"' >/dev/null 2>&1; then
  echo "FAIL: liquidctl should disconnect via WAYBAR_HWMON_ROOT corsairpsu: $liquid_hwmon" >&2
  fail=1
fi
rm -rf "$LIQUID_FAKE" "$LIQUID_CACHE"
echo "PASS: liquidctl module wiring and status script behavior"

# coolercontrol module: generator wiring + status/click (fixtures)
echo "Testing coolercontrol module wiring and status/click scripts..."
if ! "$TEST_DIR/scripts/generate/generate-settings.sh"; then
  echo "FAIL: generate-settings.sh failed before coolercontrol checks" >&2
  fail=1
fi
if ! jq -e '."custom/coolercontrol".exec | test("services/coolercontrol/coolercontrol-status\\.sh$")' "$TEST_DIR/modules/system.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/coolercontrol exec missing coolercontrol-status.sh" >&2
  fail=1
fi
if ! jq -e '."custom/coolercontrol".interval == 60' "$TEST_DIR/modules/system.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/coolercontrol interval expected 60 from module_intervals.coolercontrol" >&2
  fail=1
fi
if ! jq -e '."custom/coolercontrol"."on-scroll-up" | test("coolercontrol-click\\.sh next")' "$TEST_DIR/modules/system.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/coolercontrol scroll-up should cycle next mode" >&2
  fail=1
fi
if ! jq -e '."custom/coolercontrol"."on-scroll-down" | test("coolercontrol-click\\.sh prev")' "$TEST_DIR/modules/system.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/coolercontrol scroll-down should cycle prev mode" >&2
  fail=1
fi
if ! jq -e '."custom/coolercontrol"."on-click-right" | test("coolercontrol-click\\.sh menu")' "$TEST_DIR/modules/system.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/coolercontrol right-click should open mode menu" >&2
  fail=1
fi
if ! jq -e '.["group/hardware"].modules | index("custom/coolercontrol")' "$TEST_DIR/modules/groups.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/coolercontrol missing from group/hardware modules" >&2
  fail=1
fi
if ! jq -e '.module_intervals.coolercontrol == 60' "$TEST_DIR/data/waybar-settings.json" >/dev/null 2>&1; then
  echo "FAIL: module_intervals.coolercontrol expected 60 in compiled settings" >&2
  fail=1
fi
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
if ! echo "$cc_out" | jq -e '.class | (type == "array" and index("warning") and index("writable"))' >/dev/null 2>&1; then
  echo "FAIL: coolercontrol-status expected class [warning, writable]: $cc_out" >&2
  fail=1
fi
if ! echo "$cc_out" | jq -e '.text | test("82")' >/dev/null 2>&1; then
  echo "FAIL: coolercontrol-status text missing hot temp: $cc_out" >&2
  fail=1
fi
if ! echo "$cc_out" | jq -e '.tooltip | test("AMD Ryzen/Package")' >/dev/null 2>&1; then
  echo "FAIL: coolercontrol tooltip should join /devices name: $cc_out" >&2
  fail=1
fi
if ! echo "$cc_out" | jq -e '.tooltip | test("Mode: Default")' >/dev/null 2>&1; then
  echo "FAIL: coolercontrol tooltip should show active mode: $cc_out" >&2
  fail=1
fi
if ! echo "$cc_out" | jq -e '.tooltip | test("Token: write")' >/dev/null 2>&1; then
  echo "FAIL: coolercontrol tooltip should show write token: $cc_out" >&2
  fail=1
fi

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
if ! echo "$cc_ro" | jq -e '.class | (type == "array" and index("warning") and index("readonly"))' >/dev/null 2>&1; then
  echo "FAIL: coolercontrol-status expected class [warning, readonly]: $cc_ro" >&2
  fail=1
fi
if ! echo "$cc_ro" | jq -e '.tooltip | test("read-only")' >/dev/null 2>&1; then
  echo "FAIL: readonly tooltip missing: $cc_ro" >&2
  fail=1
fi

# API cycle next (write)
cycle_out=$(
  WAYBAR_CC_FIXTURE_DIR="$CC_FIX" \
  python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" cycle next
)
if ! echo "$cycle_out" | jq -e '.ok == true and .name == "Gaming" and .uid == "mode-game"' >/dev/null 2>&1; then
  echo "FAIL: cycle next from Default should activate Gaming: $cycle_out" >&2
  fail=1
fi
if [[ "$(cat "$CC_FIX/last_activate.txt" 2>/dev/null | tr -d '\n')" != "mode-game" ]]; then
  echo "FAIL: cycle next did not record mode-game activation" >&2
  fail=1
fi

# API cycle rejects read-only
cycle_ro=$(
  WAYBAR_CC_FIXTURE_DIR="$CC_FIX_RO" \
  python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" cycle next
) || true
if ! echo "$cycle_ro" | jq -e '.ok == false and .error == "read_only"' >/dev/null 2>&1; then
  echo "FAIL: cycle with read-only should error read_only: $cycle_ro" >&2
  fail=1
fi

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
if ! echo "$cc_missing" | jq -e '.class == "disconnected" or (.class|tostring|test("disconnected"))' >/dev/null 2>&1; then
  echo "FAIL: coolercontrol offline should emit disconnected: $cc_missing" >&2
  fail=1
fi

# Auth preference: token over ui_pass; ui_pass fallback when token fails.
# Clear fixture/cache env so curl-mock auth is not shadowed by prior fixture tests
# or a polluted parent shell (WAYBAR_CC_FIXTURE_DIR pointing at a deleted mktemp).
unset WAYBAR_CC_FIXTURE_DIR || true
CC_AUTH_BIN="$TEST_DIR/cc-auth-bin"
mkdir -p "$CC_AUTH_BIN"
CC_AUTH_LOG="$TEST_DIR/cc-auth-curl.log"
: >"$CC_AUTH_LOG"
# Mock: bad token (cc_bad*) → 401 on Bearer /status; good token → 200; password login → 200 + cookie status
cat >"$CC_AUTH_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${CC_AUTH_LOG:?}"
joined="$*"
# Emit body\nhttp_code like real curl -w
emit() { printf '%s\n%s' "$1" "$2"; }
if [[ "$joined" == *"/status"* && "$joined" == *"Authorization: Bearer"* ]]; then
  if [[ "$joined" == *"cc_bad"* ]]; then
    emit '{"error":"unauthorized"}' "401"
  else
    emit '{"devices":[]}' "200"
  fi
  exit 0
fi
if [[ "$joined" == *"/login"* ]]; then
  if [[ "$joined" != *"-X POST"* ]]; then
    emit '' "405"
    exit 0
  fi
  emit '' "200"
  exit 0
fi
if [[ "$joined" == *"/status"* ]]; then
  # cookie session after login
  emit '{"devices":[]}' "200"
  exit 0
fi
if [[ "$joined" == *"/devices"* || "$joined" == *"/modes"* || "$joined" == *"/handshake"* ]]; then
  emit '{}' "200"
  exit 0
fi
if [[ "$joined" == *"/settings"* && "$joined" == *"PATCH"* ]]; then
  emit '{}' "403"
  exit 0
fi
emit '' "000"
exit 0
EOF
chmod +x "$CC_AUTH_BIN/curl"

# Both creds, good token → bearer only (no /login)
: >"$CC_AUTH_LOG"
auth_both=$(
  PATH="$CC_AUTH_BIN:/usr/bin:/bin" \
  CC_AUTH_LOG="$CC_AUTH_LOG" \
  WAYBAR_CC_FIXTURE_DIR= \
  WAYBAR_CC_WRITE_PROBE_TTL=0 \
  WAYBAR_CC_API_URL="http://127.0.0.1:11987" \
  WAYBAR_CC_TOKEN="cc_good_token_aaaaaaaaaaaaaaaa" \
  WAYBAR_CC_UI_PASS="fallback-pass" \
  WAYBAR_CC_UI_USER="CCAdmin" \
  python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" fetch-bundle
) || true
if ! echo "$auth_both" | jq -e '.ok == true and .auth == "bearer"' >/dev/null 2>&1; then
  echo "FAIL: both creds should prefer bearer auth: $auth_both" >&2
  fail=1
fi
if grep -q '/login' "$CC_AUTH_LOG"; then
  echo "FAIL: good token should not fall back to /login. Log:" >&2
  cat "$CC_AUTH_LOG" >&2 || true
  fail=1
fi

# Meta-guard: prove cmdline WAYBAR_CC_FIXTURE_DIR= clears a poisoned parent export.
# In bash, `export VAR=poison` then `VAR= cmd` → cmd sees empty VAR (assignment wins).
# Cases that forget the empty assign inherit poison and fail under set -e; keep this pattern.
echo "Verifying CoolerControl fixture isolation meta-guard..."
: >"$CC_AUTH_LOG"
poison_auth=$(
  export WAYBAR_CC_FIXTURE_DIR=/nonexistent-poison-cc-fixture
  PATH="$CC_AUTH_BIN:/usr/bin:/bin" \
  CC_AUTH_LOG="$CC_AUTH_LOG" \
  WAYBAR_CC_FIXTURE_DIR= \
  WAYBAR_CC_WRITE_PROBE_TTL=0 \
  WAYBAR_CC_API_URL="http://127.0.0.1:11987" \
  WAYBAR_CC_TOKEN="cc_good_token_aaaaaaaaaaaaaaaa" \
  WAYBAR_CC_UI_PASS="fallback-pass" \
  WAYBAR_CC_UI_USER="CCAdmin" \
  python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" fetch-bundle
) || true
if ! echo "$poison_auth" | jq -e '.ok == true and .auth == "bearer"' >/dev/null 2>&1; then
  echo "FAIL: isolation meta-guard — poisoned WAYBAR_CC_FIXTURE_DIR must not break bearer auth: $poison_auth" >&2
  fail=1
else
  echo "PASS: CoolerControl fixture isolation meta-guard"
fi
unset WAYBAR_CC_FIXTURE_DIR || true

# Bad token + ui_pass → basic fallback
: >"$CC_AUTH_LOG"
auth_fb=$(
  PATH="$CC_AUTH_BIN:/usr/bin:/bin" \
  CC_AUTH_LOG="$CC_AUTH_LOG" \
  WAYBAR_CC_FIXTURE_DIR= \
  WAYBAR_CC_WRITE_PROBE_TTL=0 \
  WAYBAR_CC_API_URL="http://127.0.0.1:11987" \
  WAYBAR_CC_TOKEN="cc_bad_token_bbbbbbbbbbbbbbbb" \
  WAYBAR_CC_UI_PASS="fallback-pass" \
  WAYBAR_CC_UI_USER="CCAdmin" \
  python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" fetch-bundle
) || true
if ! echo "$auth_fb" | jq -e '.ok == true and .auth == "basic"' >/dev/null 2>&1; then
  echo "FAIL: bad token should fall back to ui_pass (basic): $auth_fb" >&2
  fail=1
fi
if ! grep -q 'Authorization: Bearer' "$CC_AUTH_LOG"; then
  echo "FAIL: fallback path should still try Bearer first. Log:" >&2
  cat "$CC_AUTH_LOG" >&2 || true
  fail=1
fi
if ! grep -q '/login' "$CC_AUTH_LOG"; then
  echo "FAIL: fallback path should POST /login. Log:" >&2
  cat "$CC_AUTH_LOG" >&2 || true
  fail=1
fi

# Bad token, no password → auth_failed
auth_fail=$(
  PATH="$CC_AUTH_BIN:/usr/bin:/bin" \
  CC_AUTH_LOG="$CC_AUTH_LOG" \
  WAYBAR_CC_FIXTURE_DIR= \
  WAYBAR_CC_WRITE_PROBE_TTL=0 \
  WAYBAR_CC_API_URL="http://127.0.0.1:11987" \
  WAYBAR_CC_TOKEN="cc_bad_token_bbbbbbbbbbbbbbbb" \
  WAYBAR_CC_UI_PASS="" \
  python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" fetch-bundle
) || true
if ! echo "$auth_fail" | jq -e '.ok == false and .error == "auth_failed"' >/dev/null 2>&1; then
  echo "FAIL: bad token without ui_pass should auth_failed: $auth_fail" >&2
  fail=1
fi

# Write-access probe cache: second fetch-bundle must not re-PATCH when TTL active
CC_WC_FIX=$(mktemp -d)
CC_WC_CACHE=$(mktemp -d)
echo 200 >"$CC_WC_FIX/write_http.txt"
echo '{"status":[{"status_history":[{"temp":42}]}]}' >"$CC_WC_FIX/status.json"
echo '{"devices":[{"name":"CPU"}]}' >"$CC_WC_FIX/devices.json"
echo '{"modes":[{"uid":"m1","name":"Quiet"}]}' >"$CC_WC_FIX/modes.json"
echo '{"current_mode_uid":"m1"}' >"$CC_WC_FIX/modes_active.json"
cc_w1=$(
  XDG_CACHE_HOME="$CC_WC_CACHE" \
  WAYBAR_CC_FIXTURE_DIR="$CC_WC_FIX" \
  WAYBAR_CC_WRITE_PROBE_TTL=600 \
  python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" fetch-bundle
) || true
if ! echo "$cc_w1" | jq -e '.write_access == true' >/dev/null 2>&1; then
  echo "FAIL: write cache seed expected write_access true: $cc_w1" >&2
  fail=1
fi
echo 403 >"$CC_WC_FIX/write_http.txt"
cc_w2=$(
  XDG_CACHE_HOME="$CC_WC_CACHE" \
  WAYBAR_CC_FIXTURE_DIR="$CC_WC_FIX" \
  WAYBAR_CC_WRITE_PROBE_TTL=600 \
  python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" fetch-bundle
) || true
if ! echo "$cc_w2" | jq -e '.write_access == true' >/dev/null 2>&1; then
  echo "FAIL: cached write_access should stay true after fixture flips to 403: $cc_w2" >&2
  fail=1
fi
cc_w3=$(
  XDG_CACHE_HOME="$CC_WC_CACHE" \
  WAYBAR_CC_FIXTURE_DIR="$CC_WC_FIX" \
  WAYBAR_CC_FORCE_WRITE_PROBE=1 \
  python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" fetch-bundle
) || true
if ! echo "$cc_w3" | jq -e '.write_access == false' >/dev/null 2>&1; then
  echo "FAIL: FORCE_WRITE_PROBE should refresh to false (403): $cc_w3" >&2
  fail=1
fi
if [ ! -f "$CC_WC_CACHE/waybar/coolercontrol-write.json" ]; then
  echo "FAIL: coolercontrol write cache file missing" >&2
  fail=1
fi
rm -rf "$CC_WC_FIX" "$CC_WC_CACHE"

echo "PASS: coolercontrol module wiring and status/click behavior"

# asusctl module: generator wiring + status/click (fixture CLI)
echo "Testing asusctl module wiring and status/click scripts..."
cp "$ROOT_DIR/data/waybar-settings.jsonc" "$TEST_DIR/data/waybar-settings.jsonc"
cp "$ROOT_DIR/scripts/system/asusctl-status.sh" "$ROOT_DIR/scripts/system/asusctl-click.sh" "$TEST_DIR/scripts/system/"
chmod +x "$TEST_DIR/scripts/system/asusctl-status.sh" "$TEST_DIR/scripts/system/asusctl-click.sh"
if ! "$TEST_DIR/scripts/generate/generate-settings.sh"; then
  echo "FAIL: generate-settings.sh failed before asusctl checks" >&2
  fail=1
fi
if ! "$TEST_DIR/scripts/generate/generate-module-configs.sh"; then
  echo "FAIL: generate-module-configs.sh failed before asusctl checks" >&2
  fail=1
fi
if ! jq -e '."custom/asusctl".exec | test("system/asusctl-status\\.sh$")' "$TEST_DIR/modules/utilities.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/asusctl exec missing asusctl-status.sh" >&2
  fail=1
fi
if ! jq -e '."custom/asusctl".signal == 28' "$TEST_DIR/modules/utilities.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/asusctl signal expected 28" >&2
  fail=1
fi
if ! jq -e '."custom/asusctl"."on-scroll-up" | test("asusctl-click\\.sh next")' "$TEST_DIR/modules/utilities.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/asusctl scroll-up should cycle next" >&2
  fail=1
fi
if ! jq -e '."custom/asusctl"."on-scroll-down" | test("asusctl-click\\.sh prev")' "$TEST_DIR/modules/utilities.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/asusctl scroll-down should cycle prev" >&2
  fail=1
fi
if ! jq -e '."custom/asusctl"."on-click" | test("asusctl-click\\.sh menu")' "$TEST_DIR/modules/utilities.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/asusctl left-click should open profile menu" >&2
  fail=1
fi
if ! jq -e '.["group/desk-controls"].modules | index("custom/asusctl")' "$TEST_DIR/modules/groups.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/asusctl missing from group/desk-controls" >&2
  fail=1
fi
if ! jq -e '.module_intervals.asusctl == "once" and .signals.asusctl == 28' "$TEST_DIR/data/waybar-settings.json" >/dev/null 2>&1; then
  echo "FAIL: module_intervals/signals.asusctl missing in compiled settings" >&2
  fail=1
fi
if ! bash -n "$TEST_DIR/scripts/system/asusctl-status.sh"; then
  echo "FAIL: asusctl-status.sh failed bash -n" >&2
  fail=1
fi
if ! bash -n "$TEST_DIR/scripts/system/asusctl-click.sh"; then
  echo "FAIL: asusctl-click.sh failed bash -n" >&2
  fail=1
fi

ASUS_FAKE="$TEST_DIR/fake-asusctl"
ASUS_CACHE="$TEST_DIR/asus-cache"
mkdir -p "$ASUS_FAKE" "$ASUS_CACHE"
ASUS_STATE="$ASUS_FAKE/state"
echo Balanced >"$ASUS_STATE"
cat >"$ASUS_FAKE/asusctl" <<'EOF'
#!/usr/bin/env bash
set -eu
state="${ASUS_STATE_FILE:?}"
cmd="${1:-}"
sub="${2:-}"
case "$cmd" in
  profile)
    case "$sub" in
      get)
        printf 'Active profile is %s\n' "$(cat "$state")"
        ;;
      list)
        printf '%s\n' Quiet Balanced Performance
        ;;
      set)
        printf '%s\n' "${3:?}" >"$state"
        ;;
      next)
        cur=$(cat "$state")
        case "$cur" in
          Quiet) printf 'Balanced\n' >"$state" ;;
          Balanced) printf 'Performance\n' >"$state" ;;
          *) printf 'Quiet\n' >"$state" ;;
        esac
        ;;
      *)
        echo "unknown profile sub: $sub" >&2
        exit 2
        ;;
    esac
    ;;
  battery)
    if [[ "${sub:-}" == "info" ]]; then
      echo "Current charge limit: 80%"
    fi
    ;;
  *)
    echo "unknown: $*" >&2
    exit 2
    ;;
esac
EOF
chmod +x "$ASUS_FAKE/asusctl"

asus_out=$(
  WAYBAR_HOME="$TEST_DIR" \
  XDG_CACHE_HOME="$ASUS_CACHE" \
  WAYBAR_ASUSCTL_BIN="$ASUS_FAKE/asusctl" \
  ASUS_STATE_FILE="$ASUS_STATE" \
  "$TEST_DIR/scripts/system/asusctl-status.sh" --refresh
)
if ! echo "$asus_out" | jq -e '.class == "balanced" and (.text | test("Bal")) and (.tooltip | test("Charge limit: 80%"))' >/dev/null 2>&1; then
  echo "FAIL: asusctl-status expected balanced + charge limit: $asus_out" >&2
  fail=1
fi

mkdir -p "$TEST_DIR/fakebin"
cat >"$TEST_DIR/fakebin/notify-send" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "$TEST_DIR/fakebin/notify-send"
PATH="$TEST_DIR/fakebin:/usr/bin:/bin" \
WAYBAR_HOME="$TEST_DIR" \
XDG_CACHE_HOME="$ASUS_CACHE" \
WAYBAR_ASUSCTL_BIN="$ASUS_FAKE/asusctl" \
ASUS_STATE_FILE="$ASUS_STATE" \
  "$TEST_DIR/scripts/system/asusctl-click.sh" next
if [[ "$(cat "$ASUS_STATE")" != "Performance" ]]; then
  echo "FAIL: asusctl-click next from Balanced should set Performance (got $(cat "$ASUS_STATE"))" >&2
  fail=1
fi
asus_perf=$(
  WAYBAR_HOME="$TEST_DIR" \
  XDG_CACHE_HOME="$ASUS_CACHE" \
  WAYBAR_ASUSCTL_BIN="$ASUS_FAKE/asusctl" \
  ASUS_STATE_FILE="$ASUS_STATE" \
  "$TEST_DIR/scripts/system/asusctl-status.sh" --refresh
)
if ! echo "$asus_perf" | jq -e '.class == "performance"' >/dev/null 2>&1; then
  echo "FAIL: status after next should be performance: $asus_perf" >&2
  fail=1
fi

PATH="$TEST_DIR/fakebin:/usr/bin:/bin" \
WAYBAR_HOME="$TEST_DIR" \
XDG_CACHE_HOME="$ASUS_CACHE" \
WAYBAR_ASUSCTL_BIN="$ASUS_FAKE/asusctl" \
ASUS_STATE_FILE="$ASUS_STATE" \
  "$TEST_DIR/scripts/system/asusctl-click.sh" prev
if [[ "$(cat "$ASUS_STATE")" != "Balanced" ]]; then
  echo "FAIL: asusctl-click prev from Performance should set Balanced" >&2
  fail=1
fi

asus_miss=$(
  WAYBAR_HOME="$TEST_DIR" \
  XDG_CACHE_HOME="$ASUS_CACHE" \
  WAYBAR_ASUSCTL_BIN="$ASUS_FAKE/missing-asusctl" \
  "$TEST_DIR/scripts/system/asusctl-status.sh" --refresh
)
if ! echo "$asus_miss" | jq -e '.class == "disconnected" or (.class|tostring|test("disconnected"))' >/dev/null 2>&1; then
  echo "FAIL: missing asusctl should emit disconnected: $asus_miss" >&2
  fail=1
fi

cat >"$ASUS_FAKE/asusctl-down2" <<'EOF'
#!/usr/bin/env bash
echo "asusd is not running, start it with systemctl start asusd"
exit 0
EOF
chmod +x "$ASUS_FAKE/asusctl-down2"
asus_down=$(
  WAYBAR_HOME="$TEST_DIR" \
  XDG_CACHE_HOME="$ASUS_CACHE" \
  WAYBAR_ASUSCTL_BIN="$ASUS_FAKE/asusctl-down2" \
  "$TEST_DIR/scripts/system/asusctl-status.sh" --refresh
)
if ! echo "$asus_down" | jq -e '.class == "disconnected" or (.class|tostring|test("disconnected"))' >/dev/null 2>&1; then
  echo "FAIL: asusd-down message should emit disconnected: $asus_down" >&2
  fail=1
fi
echo "PASS: asusctl module wiring and status/click behavior"

# nvme / openlinkhub / rgb / amdgpu fallback / solaar battery / fanctl note
echo "Testing nvme, openlinkhub, rgb, amdgpu fallback, and supplements..."
cp "$ROOT_DIR/data/waybar-settings.jsonc" "$TEST_DIR/data/waybar-settings.jsonc"
mkdir -p "$TEST_DIR/scripts/system" "$TEST_DIR/scripts/services/openlinkhub" "$TEST_DIR/scripts/services/devices" "$TEST_DIR/scripts/infra"
cp "$ROOT_DIR/scripts/system/nvme-status.sh" "$ROOT_DIR/scripts/system/rgb-status.sh" \
  "$ROOT_DIR/scripts/system/fans-status.sh" "$ROOT_DIR/scripts/system/gpu-status.sh" \
  "$TEST_DIR/scripts/system/"
cp "$ROOT_DIR/scripts/services/openlinkhub/openlinkhub-status.sh" "$TEST_DIR/scripts/services/openlinkhub/"
cp "$ROOT_DIR/scripts/services/devices/device-battery-status.sh" "$TEST_DIR/scripts/services/devices/"
cp "$ROOT_DIR/scripts/infra/system-metrics-collector.sh" "$ROOT_DIR/scripts/infra/metrics-icons-build.sh" \
  "$TEST_DIR/scripts/infra/"
chmod +x "$TEST_DIR/scripts/system/"*.sh "$TEST_DIR/scripts/services/openlinkhub/"*.sh \
  "$TEST_DIR/scripts/services/devices/"*.sh "$TEST_DIR/scripts/infra/"*.sh

if ! "$TEST_DIR/scripts/generate/generate-settings.sh"; then
  echo "FAIL: generate-settings.sh failed before nvme/olh checks" >&2
  fail=1
fi
if ! "$TEST_DIR/scripts/generate/generate-module-configs.sh"; then
  echo "FAIL: generate-module-configs.sh failed before rgb checks" >&2
  fail=1
fi
if ! jq -e '."custom/nvme".exec | test("system/nvme-status\\.sh$")' "$TEST_DIR/modules/system.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/nvme exec missing" >&2
  fail=1
fi
if ! jq -e '.["group/hardware"].modules | index("custom/nvme") and index("custom/openlinkhub")' "$TEST_DIR/modules/groups.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: hardware group missing nvme/openlinkhub" >&2
  fail=1
fi
if ! jq -e '."custom/openlinkhub".exec | test("openlinkhub-status\\.sh$")' "$TEST_DIR/modules/system.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/openlinkhub exec missing" >&2
  fail=1
fi
if ! jq -e '."custom/rgb".exec | test("system/rgb-status\\.sh$")' "$TEST_DIR/modules/utilities.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: custom/rgb exec missing" >&2
  fail=1
fi
if ! jq -e '.["group/tools"].modules | index("custom/rgb")' "$TEST_DIR/modules/groups.generated.jsonc" >/dev/null 2>&1; then
  echo "FAIL: tools group missing custom/rgb" >&2
  fail=1
fi

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
if ! echo "$nvme_empty" | jq -e '.class == "disconnected" or (.class|tostring|test("disconnected"))' >/dev/null 2>&1; then
  echo "FAIL: empty nvme hwmon should disconnect: $nvme_empty" >&2
  fail=1
fi

# OpenLinkHub fixture — presence-first (device count), exclude cluster
OLH_FIX="$TEST_DIR/olh-api.json"
OLH_CACHE="$TEST_DIR/olh-cache"
mkdir -p "$OLH_CACHE"
if ! jq -e '.services.openlinkhub.prefer_presence == true' "$TEST_DIR/data/waybar-settings.json" >/dev/null 2>&1; then
  echo "FAIL: services.openlinkhub.prefer_presence expected true in compiled settings" >&2
  fail=1
fi
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
if ! echo "$olh_out" | jq -e '(.text | test("2")) and .class == "normal"' >/dev/null 2>&1; then
  echo "FAIL: openlinkhub fixture expected presence count 2: $olh_out" >&2
  fail=1
fi
if ! echo "$olh_out" | jq -e '.tooltip | test("Commander") and test("HX1500i")' >/dev/null 2>&1; then
  echo "FAIL: openlinkhub tooltip should list real devices: $olh_out" >&2
  fail=1
fi
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
if ! echo "$olh_temp" | jq -e '(.text | test("71")) and .class == "warning"' >/dev/null 2>&1; then
  echo "FAIL: openlinkhub prefer_presence=false expected hot 71 warning: $olh_temp" >&2
  fail=1
fi
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
if ! echo "$olh_psu" | jq -e '(.text | test("1")) and (.tooltip | test("PSU module|corsairpsu"; "i"))' >/dev/null 2>&1; then
  echo "FAIL: openlinkhub PSU-only should point at PSU module: $olh_psu" >&2
  fail=1
fi
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
if ! echo "$olh_hwmon" | jq -e '.tooltip | test("PSU module|corsairpsu"; "i")' >/dev/null 2>&1; then
  echo "FAIL: openlinkhub should detect corsairpsu via WAYBAR_HWMON_ROOT: $olh_hwmon" >&2
  fail=1
fi
olh_down=$(
  WAYBAR_HOME="$TEST_DIR" XDG_CACHE_HOME="$OLH_CACHE" \
  WAYBAR_OLH_API_URL="http://127.0.0.1:9" \
  WAYBAR_OLH_FORCE_ACTIVE=0 \
  "$TEST_DIR/scripts/services/openlinkhub/openlinkhub-status.sh" --refresh
)
if ! echo "$olh_down" | jq -e '.class == "disconnected" or (.class|tostring|test("disconnected"))' >/dev/null 2>&1; then
  echo "FAIL: openlinkhub inactive should disconnect: $olh_down" >&2
  fail=1
fi

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
if ! echo "$rgb_idle" | jq -e '.class == "disconnected" or (.class|tostring|test("disconnected"))' >/dev/null 2>&1; then
  echo "FAIL: idle rgb should disconnect: $rgb_idle" >&2
  fail=1
fi
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
if ! echo "$rgb_on" | jq -e '(.text | test("2")) and (.tooltip | test("OpenRGB"))' >/dev/null 2>&1; then
  echo "FAIL: rgb with openrgb list should show 2 devices: $rgb_on" >&2
  fail=1
fi

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
if ! echo "$batt_out" | jq -e '(.text | test("18")) and (.tooltip | test("solaar")) and .class == "warning"' >/dev/null 2>&1; then
  echo "FAIL: solaar battery fallback expected 18% warning: $batt_out" >&2
  fail=1
fi

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
if ! echo "$fan_dedupe" | jq -e '(.text | test("1525")) and (.tooltip | test("CPU_Opt"))' >/dev/null 2>&1; then
  echo "FAIL: fans should show asusec CPU RPM: $fan_dedupe" >&2
  fail=1
fi
if ! echo "$fan_dedupe" | jq -e '.tooltip | test("Chassis \\(nct6799 max\\): 1410")' >/dev/null 2>&1; then
  echo "FAIL: fans should show nct6799 chassis max 1410: $fan_dedupe" >&2
  fail=1
fi
if ! echo "$fan_dedupe" | jq -e '.tooltip | test("see PSU module")' >/dev/null 2>&1; then
  echo "FAIL: fans should defer PSU fan to PSU module: $fan_dedupe" >&2
  fail=1
fi
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
if ! echo "$fan_nopasu" | jq -e '(.text | test("1000")) and (.tooltip | test("PSU Fan: N/A"))' >/dev/null 2>&1; then
  echo "FAIL: fans without corsairpsu should show CPU 1000 + PSU Fan N/A: $fan_nopasu" >&2
  fail=1
fi

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

echo "PASS: nvme/openlinkhub/rgb/amdgpu/solaar/fanctl supplements"

# Validate must reject flat scripts/<file>.sh paths (journal: No such file after domain move)
echo "Verifying validate rejects flat script paths..."
FLAT_DIR=$(mktemp -d)
mkdir -p "$FLAT_DIR/modules" "$FLAT_DIR/includes" "$FLAT_DIR/layouts" "$FLAT_DIR/data" "$FLAT_DIR/scripts/ci"
cp "$ROOT_DIR/scripts/ci/validate-generated-config.sh" "$FLAT_DIR/scripts/ci/"
printf '{}\n' >"$FLAT_DIR/data/waybar-settings.json"
printf '{}\n' >"$FLAT_DIR/modules/workspaces.generated.jsonc"
cat >"$FLAT_DIR/modules/system.generated.jsonc" <<'JSON'
{
  "custom/cpu": {
    "exec": "$WAYBAR_HOME/scripts/cpu-status.sh"
  }
}
JSON
if WAYBAR_HOME="$FLAT_DIR" "$FLAT_DIR/scripts/ci/validate-generated-config.sh" >/dev/null 2>&1; then
  echo "FAIL: validate should reject flat \$WAYBAR_HOME/scripts/cpu-status.sh" >&2
  fail=1
else
  echo "PASS: validate rejects flat scripts/<file> paths"
fi
# Missing domain script should also fail existence check
mkdir -p "$FLAT_DIR/scripts/system"
cat >"$FLAT_DIR/modules/system.generated.jsonc" <<'JSON'
{
  "custom/cpu": {
    "exec": "$WAYBAR_HOME/scripts/system/cpu-status.sh"
  }
}
JSON
# path is domain-shaped but file missing
if WAYBAR_HOME="$FLAT_DIR" "$FLAT_DIR/scripts/ci/validate-generated-config.sh" >/dev/null 2>&1; then
  echo "FAIL: validate should reject missing scripts/system/cpu-status.sh" >&2
  fail=1
else
  echo "PASS: validate rejects missing resolved script paths"
fi
rm -rf "$FLAT_DIR"

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
if ! printf '%s' "$psu_out" | jq -e '.text | test("150W")' >/dev/null 2>&1; then
  echo "FAIL: psu WAYBAR_HWMON_ROOT should report 150W: $psu_out" >&2
  fail=1
fi
# Meta-guard: exported poison root must not override an explicit per-command root
# (same bash assignment rule as the CoolerControl fixture meta-guard above).
psu_poison=$(
  export WAYBAR_HWMON_ROOT=/nonexistent-poison-hwmon
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  XDG_CACHE_HOME="$PORT_CACHE" WAYBAR_HWMON_ROOT="$PSU_HWMON" \
    "$TEST_DIR/scripts/system/psu-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
if ! printf '%s' "$psu_poison" | jq -e '.text | test("150W")' >/dev/null 2>&1; then
  echo "FAIL: isolation meta-guard — poisoned WAYBAR_HWMON_ROOT must not override cmdline root: $psu_poison" >&2
  fail=1
fi
unset WAYBAR_HWMON_ROOT || true
PSU_EMPTY=$(mktemp -d)
rm -f "$PORT_WB/corsairpsu-path.txt" "$PORT_WB/psu-status.json"
rm -rf "$PSU_HWMON" # drop cached path target if any residual
psu_empty=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  XDG_CACHE_HOME="$PORT_CACHE" WAYBAR_HWMON_ROOT="$PSU_EMPTY" \
    "$TEST_DIR/scripts/system/psu-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
if ! printf '%s' "$psu_empty" | jq -e '.class == "disconnected"' >/dev/null 2>&1; then
  echo "FAIL: psu empty hwmon should disconnect: $psu_empty" >&2
  fail=1
fi
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
if ! printf '%s' "$batt_out" | jq -e '(.text | test("42%")) and (.tooltip | test("sysfs"))' >/dev/null 2>&1; then
  echo "FAIL: device-battery WAYBAR_POWER_SUPPLY_ROOT: $batt_out" >&2
  fail=1
fi
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
if ! printf '%s' "$apt_upd" | jq -e '(.tooltip | test("APT updates: 2")) and (.tooltip | test("Backend: apt"))' >/dev/null 2>&1; then
  echo "FAIL: updates apt backend: $apt_upd" >&2
  fail=1
fi
rm -f "$PORT_WB/updates-status.json"
dnf_upd=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  XDG_CACHE_HOME="$PORT_CACHE" WAYBAR_UPDATES_BACKEND=dnf WAYBAR_BACKGROUND=0 \
  PATH="$UPD_BIN:/usr/bin:/bin" \
    "$TEST_DIR/scripts/services/sync/updates-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
if ! printf '%s' "$dnf_upd" | jq -e '(.tooltip | test("DNF updates: 2")) and (.tooltip | test("Backend: dnf"))' >/dev/null 2>&1; then
  echo "FAIL: updates dnf backend: $dnf_upd" >&2
  fail=1
fi
rm -f "$PORT_WB/updates-status.json"
none_upd=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  XDG_CACHE_HOME="$PORT_CACHE" WAYBAR_UPDATES_BACKEND=none WAYBAR_BACKGROUND=0 \
  PATH="$UPD_BIN:/usr/bin:/bin" \
    "$TEST_DIR/scripts/services/sync/updates-status.sh" --refresh 2>/dev/null | tail -n 1
) || true
if ! printf '%s' "$none_upd" | jq -e '(.text | test("  0")) and (.tooltip | test("Backend: none"))' >/dev/null 2>&1; then
  echo "FAIL: updates none backend should be zero: $none_upd" >&2
  fail=1
fi
rm -rf "$UPD_BIN"

# updates-review: apt path without paru (settings apps.apt_update)
REV_BIN=$(mktemp -d)
REV_HOME=$(mktemp -d)
mkdir -p "$REV_HOME/data" "$REV_HOME/scripts/"{lib,tools,services/sync}
cp "$ROOT_DIR/scripts/services/sync/updates-review.sh" "$REV_HOME/scripts/services/sync/"
cp "$ROOT_DIR/scripts/lib/waybar-settings.sh" "$ROOT_DIR/scripts/lib/compositor-session.sh" "$REV_HOME/scripts/lib/"
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
