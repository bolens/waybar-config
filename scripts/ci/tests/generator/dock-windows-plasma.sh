#!/usr/bin/env bash
# Plasma dock-windows: slot group layout, qdbus stubs, focus-by-slot (no rofi).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "dock-windows-plasma"
waybar_test_gen_sandbox

echo "Testing Plasma dock-windows slots + KDE status path..."

mkdir -p "$TEST_DIR/scripts/dock" "$TEST_DIR/scripts/lib" "$TEST_DIR/scripts/generate"
cp "$ROOT_DIR/scripts/dock/dock-windows-status.sh" \
  "$ROOT_DIR/scripts/dock/dock-windows-click.sh" \
  "$ROOT_DIR/scripts/dock/dock-windows-signal.sh" \
  "$ROOT_DIR/scripts/dock/dock-windows-query.sh" \
  "$ROOT_DIR/scripts/dock/dock-windows-slot-status.sh" \
  "$TEST_DIR/scripts/dock/"
cp "$ROOT_DIR/scripts/lib/dock-windows-kde-lib.sh" \
  "$ROOT_DIR/scripts/lib/dock-windows-kde-lib.py" \
  "$ROOT_DIR/scripts/lib/compositor-session.sh" \
  "$ROOT_DIR/scripts/lib/waybar-cache-helpers.sh" \
  "$ROOT_DIR/scripts/lib/waybar-settings.sh" \
  "$TEST_DIR/scripts/lib/"
cp "$ROOT_DIR/scripts/generate/generate-dock-windows-modules.sh" "$TEST_DIR/scripts/generate/"
chmod +x "$TEST_DIR"/scripts/dock/*.sh \
  "$TEST_DIR/scripts/lib/dock-windows-kde-lib.sh" \
  "$TEST_DIR/scripts/lib/dock-windows-kde-lib.py" \
  "$TEST_DIR/scripts/generate/generate-dock-windows-modules.sh"

for f in \
  "$TEST_DIR/scripts/dock/dock-windows-query.sh" \
  "$TEST_DIR/scripts/dock/dock-windows-slot-status.sh" \
  "$TEST_DIR/scripts/dock/dock-windows-click.sh" \
  "$TEST_DIR/scripts/generate/generate-dock-windows-modules.sh"; do
  if ! bash -n "$f"; then
    echo "FAIL: bash -n $f" >&2
    fail=1
  fi
done

if ! waybar_test_gen_modules; then
  echo "FAIL: default generate failed" >&2
  fail=1
fi

waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" \
  '.dock_windows.enabled == true' \
  "default dock_windows.enabled should be true"
waybar_test_assert_json_file_jq "$TEST_DIR/layouts/bottom.generated.jsonc" \
  '."modules-center" | index("group/dock-windows")' \
  "default enabled → bottom center includes group/dock-windows"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/dock-windows.generated.jsonc" \
  'has("custom/dock-win-0")' \
  "dock-win-0 slot module should be generated"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/dock-windows.generated.jsonc" \
  '."custom/dock-win-0".exec | test("dock-windows-slot-status")' \
  "dock-win-0 exec should use slot status script"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/dock-windows.generated.jsonc" \
  '."custom/dock-win-0"."on-click" | test("focus 0")' \
  "dock-win-0 on-click should focus slot 0"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups-dock-windows.generated.jsonc" \
  '."group/dock-windows".modules | index("custom/dock-win-0")' \
  "group/dock-windows should list slot modules"
# No rofi activate binding on slots
if jq -r 'to_entries[] | .value["on-click"] // empty' "$TEST_DIR/modules/dock-windows.generated.jsonc" \
  | grep -q 'activate'; then
  echo "FAIL: dock slots must not use rofi activate on-click" >&2
  fail=1
fi

# --- Golden WindowsRunner parse ---
GOLDEN="$ROOT_DIR/scripts/ci/lib/fixtures/windows-runner/golden-basic.txt"
parse_json=$(python3 "$TEST_DIR/scripts/lib/dock-windows-kde-lib.py" parse --json <"$GOLDEN")
waybar_test_assert_jq "$parse_json" 'length == 4' "golden fixture should parse 4 windows: $parse_json"

# --- KDE slot status with qdbus stub ---
waybar_test_install_path_stubs
GOLDEN_DATA=$(cat "$GOLDEN")
waybar_test_write_bin_stub qdbus6 <<EOF
#!/usr/bin/env sh
echo "\$*" >>"\$WAYBAR_TEST_QDBUS_LOG"
case " \$* " in
  *"org.kde.krunner1.Match"*)
    cat <<'GOLD'
$GOLDEN_DATA
GOLD
    ;;
  *"org.kde.krunner1.Run"*)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF

export WAYBAR_TEST_QDBUS_LOG="$TEST_DIR/qdbus-calls.log"
: >"$WAYBAR_TEST_QDBUS_LOG"
CACHE="$TEST_DIR/cache-kde"
rm -rf "$CACHE"
mkdir -p "$CACHE/waybar" "$TEST_DIR/runtime"
export XDG_CACHE_HOME="$CACHE" XDG_RUNTIME_DIR="$TEST_DIR/runtime"

# Seed active title so slot focused class can resolve
printf '%s' 'Terminal on DP-1' >"$CACHE/waybar/active-window-title-DP-1.raw"

slot0=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    WAYBAR_COMPOSITOR=kde \
    "$TEST_DIR/scripts/dock/dock-windows-slot-status.sh" 0 DP-1
)
waybar_test_assert_jq "$slot0" '.text != ""' "slot 0 should show an icon: $slot0"
waybar_test_assert_jq "$slot0" '.class | index("dock-win-hit")' "slot 0 should be clickable: $slot0"
waybar_test_assert_jq "$slot0" '.class | index("dock-win-active")' \
  "slot matching active title should be dock-win-active: $slot0"
waybar_test_assert_jq "$slot0" '.tooltip | test("Terminal")' "slot tooltip should be title: $slot0"

# Empty slot beyond window count → hidden
slot15=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    WAYBAR_COMPOSITOR=kde \
    "$TEST_DIR/scripts/dock/dock-windows-slot-status.sh" 15 DP-1
)
waybar_test_assert_jq "$slot15" '.class | index("hidden")' "empty slot should be hidden: $slot15"

# Focus click writes Run (no rofi)
: >"$WAYBAR_TEST_QDBUS_LOG"
WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_COMPOSITOR=kde \
  XDG_CACHE_HOME="$CACHE" XDG_RUNTIME_DIR="$TEST_DIR/runtime" \
  "$TEST_DIR/scripts/dock/dock-windows-click.sh" focus 0 DP-1
if ! grep -q 'org.kde.krunner1.Run' "$WAYBAR_TEST_QDBUS_LOG"; then
  echo "FAIL: focus slot should call WindowsRunner Run" >&2
  cat "$WAYBAR_TEST_QDBUS_LOG" >&2 || true
  fail=1
else
  echo "PASS: focus slot calls WindowsRunner Run"
fi
if grep -qi rofi "$WAYBAR_TEST_QDBUS_LOG" 2>/dev/null; then
  echo "FAIL: dock click must not invoke rofi" >&2
  fail=1
fi

# Missing qdbus messaging
waybar_test_write_bin_stub notify-send <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >>"${WAYBAR_TEST_NOTIFY_LOG:-/dev/null}"
EOF
export WAYBAR_TEST_NOTIFY_LOG="$TEST_DIR/notify.log"
: >"$WAYBAR_TEST_NOTIFY_LOG"
WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_COMPOSITOR=kde WAYBAR_TEST_NO_QDBUS=1 \
  XDG_CACHE_HOME="$CACHE" XDG_RUNTIME_DIR="$TEST_DIR/runtime" \
  "$TEST_DIR/scripts/dock/dock-windows-click.sh" focus 0 DP-1 || true
if ! grep -q 'Install qt6-tools (qdbus6)' "$WAYBAR_TEST_NOTIFY_LOG"; then
  echo "FAIL: click without qdbus6 should notify install message" >&2
  cat "$WAYBAR_TEST_NOTIFY_LOG" >&2 || true
  fail=1
fi

waybar_test_end
