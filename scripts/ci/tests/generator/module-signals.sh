#!/usr/bin/env bash
# Module RTMIN registry: unique offsets, keyed refresh wiring, waybar-signal.sh behavior.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "module-signals"
waybar_test_gen_sandbox

if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before module-signals checks" >&2
  fail=1
fi

echo "Testing signals.* uniqueness via check-settings-schema..."
if ! WAYBAR_HOME="$TEST_DIR" bash "$ROOT_DIR/scripts/ci/check-settings-schema.sh" >/dev/null; then
  echo "FAIL: check-settings-schema.sh rejected compiled settings" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" '
  (.signals | length) > 0
  and ((.signals | to_entries | map(.value) | unique | length) == (.signals | length))
' "signals.* must be non-empty with unique offsets"

echo "Testing every generated module signal resolves to a registry key..."
# Collect signal values from generated custom modules; each must appear in signals.*.
sig_map_ok=$(
  jq -n --slurpfile s "$TEST_DIR/data/waybar-settings.json" '
    ($s[0].signals // {}) as $sig
    | ($sig | to_entries | map({(.value | tostring): .key}) | add) as $by_n
    | $by_n
  '
)
mod_files=(
  "$TEST_DIR"/modules/*.generated.jsonc
)
orphan_report=$(
  for f in "${mod_files[@]}"; do
    [ -f "$f" ] || continue
    jq -r --argjson byn "$sig_map_ok" --arg file "$f" '
      to_entries[]
      | select(.value | type == "object" and has("signal"))
      | . as $m
      | ($m.value.signal | tostring) as $n
      | if ($byn[$n] // null) == null then
          "\($file):\($m.key) signal=\($n) not in signals.*"
        else empty end
    ' "$f" 2>/dev/null || true
  done
)
if [ -n "$orphan_report" ]; then
  echo "FAIL: generated module signal(s) missing from signals.*:" >&2
  printf '  %s\n' "$orphan_report" >&2
  fail=1
fi

echo "Testing keyed middle/right refresh (no baked numeric waybar-signal.sh)..."
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" '
  (."custom/kdeconnect"."on-click-middle" | test("waybar-signal\\.sh kdeconnect"))
  and (."custom/device-notifier"."on-click-right" | test("waybar-signal\\.sh device_notifier"))
  and (."custom/vaults"."on-click-right" | test("waybar-signal\\.sh vaults"))
  and (."custom/touchpad"."on-click-right" | test("waybar-signal\\.sh touchpad"))
  and (."custom/rgb"."on-click-middle" | test("waybar-signal\\.sh rgb"))
  and (."custom/asusctl"."on-click-middle" | test("waybar-signal\\.sh asusctl"))
  and (."custom/device-battery"."on-click-middle" | test("waybar-signal\\.sh device_battery"))
  and (."custom/weather"."on-click-middle" | test("waybar-signal\\.sh weather"))
  and (."custom/github"."on-click-middle" | test("waybar-signal\\.sh github"))
' "utilities refresh clicks must use signals.* keys"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/system.generated.jsonc" '
  (."custom/coolercontrol"."on-click-middle" | test("waybar-signal\\.sh coolercontrol"))
  and (."custom/openlinkhub"."on-click-middle" | test("waybar-signal\\.sh openlinkhub"))
  and (."custom/homelab"."on-click-middle" | test("waybar-signal\\.sh homelab"))
' "system polling modules must signal on middle-click refresh"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/network-custom.generated.jsonc" '
  (."custom/vpnstatus"."on-click-middle" | test("waybar-signal\\.sh vpn"))
  and (."custom/tailscale"."on-click-middle" | test("waybar-signal\\.sh tailscale"))
' "vpn/tailscale middle-click must use keyed signals"

# Tooltip Pango escape / notifications rich tooltips: scripts/ci/tests/generator/tooltip-pango-escape.sh

if grep -RE 'waybar-signal\.sh [0-9]+' \
  "$TEST_DIR/modules/"*.generated.jsonc \
  "$TEST_DIR/scripts/generate/"*.sh 2>/dev/null; then
  echo "FAIL: generators/modules must not bake numeric waybar-signal.sh offsets" >&2
  fail=1
fi

echo "Testing click/listener scripts prefer keys (not bare RTMIN numbers)..."
# Call sites use: "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" <key> …
for pair in \
  "scripts/workspaces/workspaces-click.sh:waybar-signal.sh\" workspaces" \
  "scripts/system/keyboard-layout-click.sh:waybar-signal.sh\" keyboard_layout" \
  "scripts/tools/pomodoro-click.sh:waybar-signal.sh\" pomodoro" \
  "scripts/services/devices/streamdeck-click.sh:waybar-signal.sh\" streamdeck" \
  "scripts/dock/dock-windows-signal.sh:waybar-signal.sh\" dock_windows" \
  "scripts/dock/dock-launcher.sh:waybar-signal.sh\" dock_apps"; do
  path="${pair%%:*}"
  needle="${pair#*:}"
  if ! grep -Fq "$needle" "$TEST_DIR/$path"; then
    echo "FAIL: $path should call waybar-signal.sh with key (needle=$needle)" >&2
    fail=1
  fi
done
if grep -E 'waybar-signal\.sh [0-9]+' \
  "$TEST_DIR/scripts/workspaces/workspaces-click.sh" \
  "$TEST_DIR/scripts/system/keyboard-layout-click.sh" \
  "$TEST_DIR/scripts/tools/pomodoro-click.sh" \
  "$TEST_DIR/scripts/services/devices/streamdeck-click.sh" \
  "$TEST_DIR/scripts/dock/dock-windows-signal.sh" \
  "$TEST_DIR/scripts/dock/dock-launcher.sh" 2>/dev/null; then
  echo "FAIL: click helpers must not pass numeric offsets to waybar-signal.sh" >&2
  fail=1
fi

echo "Testing waybar-signal.sh key lookup + clear stderr on unknown keys..."
cp -f "$ROOT_DIR/scripts/lib/waybar-signal.sh" "$TEST_DIR/scripts/lib/waybar-signal.sh"
chmod +x "$TEST_DIR/scripts/lib/waybar-signal.sh"
# Hermetic pkill stub — record RTMIN args instead of signaling a real Waybar.
mkdir -p "$TEST_DIR/bin"
cat >"$TEST_DIR/bin/pkill" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >>"${WAYBAR_HOME}/bin/pkill.log"
EOF
chmod +x "$TEST_DIR/bin/pkill"
export PATH="$TEST_DIR/bin:$PATH"
: >"$TEST_DIR/bin/pkill.log"

err=$(
  WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/lib/waybar-signal.sh" weather 2>&1 >/dev/null || true
)
if ! grep -q -- '-RTMIN+34' "$TEST_DIR/bin/pkill.log"; then
  echo "FAIL: waybar-signal.sh weather should resolve to RTMIN+34: $(cat "$TEST_DIR/bin/pkill.log")" >&2
  fail=1
fi
if [ -n "$err" ]; then
  echo "FAIL: successful keyed signal should be quiet on stderr: $err" >&2
  fail=1
fi

: >"$TEST_DIR/bin/pkill.log"
err=$(
  WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/lib/waybar-signal.sh" not_a_real_signal 2>&1 >/dev/null || true
)
if [ -s "$TEST_DIR/bin/pkill.log" ]; then
  echo "FAIL: unknown key must not pkill: $(cat "$TEST_DIR/bin/pkill.log")" >&2
  fail=1
fi
if ! printf '%s' "$err" | grep -qi 'unknown'; then
  echo "FAIL: unknown key should log a clear stderr hint, got: ${err:-<empty>}" >&2
  fail=1
fi

: >"$TEST_DIR/bin/pkill.log"
err=$(
  WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/lib/waybar-signal.sh" 16 2>&1 >/dev/null || true
)
if ! grep -q -- '-RTMIN+16' "$TEST_DIR/bin/pkill.log"; then
  echo "FAIL: numeric offset 16 should still work: $(cat "$TEST_DIR/bin/pkill.log")" >&2
  fail=1
fi

cache_probe="$TEST_DIR/cache/probe.json"
mkdir -p "$TEST_DIR/cache"
echo '{}' >"$cache_probe"
: >"$TEST_DIR/bin/pkill.log"
WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/lib/waybar-signal.sh" workspaces "$cache_probe" >/dev/null 2>&1 || true
if [ -f "$cache_probe" ]; then
  echo "FAIL: waybar-signal.sh should invalidate listed cache files" >&2
  fail=1
fi

waybar_test_end
