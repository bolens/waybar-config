#!/usr/bin/env bash
# Pomodoro module wiring + toggle/pause/reset/skip state machine.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "pomodoro"
waybar_test_gen_sandbox

echo "Testing pomodoro wiring and click/status scripts..."
cp "$ROOT_DIR/scripts/tools/pomodoro-status.sh" "$ROOT_DIR/scripts/tools/pomodoro-click.sh" \
  "$TEST_DIR/scripts/tools/"
chmod +x "$TEST_DIR/scripts/tools/pomodoro-status.sh" "$TEST_DIR/scripts/tools/pomodoro-click.sh"
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before pomodoro checks" >&2
  fail=1
fi

waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" \
  '."custom/pomodoro".exec | test("tools/pomodoro-status\\.sh$")' \
  "custom/pomodoro exec missing pomodoro-status.sh"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" \
  '."custom/pomodoro".signal == 31 and ."custom/pomodoro".interval == 1' \
  "custom/pomodoro signal/interval expected 31 / 1"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" \
  '."custom/pomodoro"."on-click" | test("pomodoro-click\\.sh toggle")' \
  "custom/pomodoro left-click should toggle"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '."group/tools".modules | index("custom/pomodoro")' \
  "custom/pomodoro missing from group/tools"
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" \
  '.pomodoro.work_min == 25 and .signals.pomodoro == 31' \
  "pomodoro settings keys missing"

if ! bash -n "$TEST_DIR/scripts/tools/pomodoro-status.sh"; then
  echo "FAIL: pomodoro-status.sh failed bash -n" >&2
  fail=1
fi
if ! bash -n "$TEST_DIR/scripts/tools/pomodoro-click.sh"; then
  echo "FAIL: pomodoro-click.sh failed bash -n" >&2
  fail=1
fi

mkdir -p "$TEST_DIR/scripts/lib"
cp "$ROOT_DIR/scripts/ci/lib/fixtures/script-stubs/waybar-signal.sh" "$TEST_DIR/scripts/lib/waybar-signal.sh"
chmod +x "$TEST_DIR/scripts/lib/waybar-signal.sh"

CACHE="$TEST_DIR/pom-cache"
rm -rf "$CACHE"
mkdir -p "$CACHE"

idle=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" XDG_CACHE_HOME="$CACHE" \
    "$TEST_DIR/scripts/tools/pomodoro-status.sh"
)
waybar_test_assert_jq "$idle" '.class == "idle" and (.text | test("󰔟"))' "pomodoro idle expected: $idle"

WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" XDG_CACHE_HOME="$CACHE" \
  "$TEST_DIR/scripts/tools/pomodoro-click.sh" toggle
run=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" XDG_CACHE_HOME="$CACHE" \
    "$TEST_DIR/scripts/tools/pomodoro-status.sh"
)
waybar_test_assert_jq "$run" '.class == "work" and (.tooltip | test("running")) and (.text | test("25:"))' \
  "pomodoro after toggle should be work/running: $run"

WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" XDG_CACHE_HOME="$CACHE" \
  "$TEST_DIR/scripts/tools/pomodoro-click.sh" toggle
paused=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" XDG_CACHE_HOME="$CACHE" \
    "$TEST_DIR/scripts/tools/pomodoro-status.sh"
)
waybar_test_assert_jq "$paused" '.class == "work" and (.tooltip | test("paused"))' \
  "pomodoro second toggle should pause: $paused"

WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" XDG_CACHE_HOME="$CACHE" \
  "$TEST_DIR/scripts/tools/pomodoro-click.sh" skip
break_out=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" XDG_CACHE_HOME="$CACHE" \
    "$TEST_DIR/scripts/tools/pomodoro-status.sh"
)
waybar_test_assert_jq "$break_out" '.class == "break" and (.tooltip | test("Short break|Long break"))' \
  "pomodoro skip from work should enter break: $break_out"

WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" XDG_CACHE_HOME="$CACHE" \
  "$TEST_DIR/scripts/tools/pomodoro-click.sh" reset
idle2=$(
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" XDG_CACHE_HOME="$CACHE" \
    "$TEST_DIR/scripts/tools/pomodoro-status.sh"
)
waybar_test_assert_jq "$idle2" '.class == "idle"' "pomodoro reset should return idle: $idle2"
if [ -f "$CACHE/pomodoro.state" ]; then
  echo "FAIL: reset should remove pomodoro.state" >&2
  fail=1
fi

waybar_test_end
