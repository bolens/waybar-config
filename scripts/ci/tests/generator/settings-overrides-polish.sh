#!/usr/bin/env bash
# Polish default click wiring (no on_click overrides).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "settings-overrides-polish"
waybar_test_gen_sandbox
if ! waybar_test_gen_default >/dev/null; then
  echo "FAIL: default generate failed before polish clicks" >&2
  exit 1
fi

echo "Testing polish default click wiring (no on_click overrides)..."
cp "$ROOT_DIR/scripts/ci/lib/fixtures/settings/generator-polish-clicks.jsonc" \
  "$TEST_DIR/data/waybar-settings.jsonc"
if ! waybar_test_gen_modules >/dev/null; then
  echo "FAIL: generate failed for polish defaults" >&2
  fail=1
fi
clean_utils_polish=$(waybar_test_read_jsonc "$TEST_DIR/modules/utilities.generated.jsonc")
clean_sys_polish=$(waybar_test_read_jsonc "$TEST_DIR/modules/system.generated.jsonc")
clean_audio_polish=$(waybar_test_read_jsonc "$TEST_DIR/modules/audio.generated.jsonc")
waybar_test_assert_jq "$clean_utils_polish" '."custom/github"."on-click" | test("github.polish/notifications")' "polish default github left-click should use apps.github_notifications"
waybar_test_assert_jq "$clean_utils_polish" '."custom/github"."on-click-right" | test("github.polish/home")' "polish default github right-click should use apps.github_home"
waybar_test_assert_jq "$clean_utils_polish" '."custom/github"."on-click-middle" | test("github-status.sh --refresh")' "polish default github middle-click should refresh"
waybar_test_assert_jq "$clean_utils_polish" '."custom/streamdeck"."on-click-right" | test("POLISH_STREAMDECK")' "polish default streamdeck right-click should use streamdeck.service_name"
waybar_test_assert_jq "$clean_sys_polish" '."custom/syncthing"."on-click-right" | test("POLISH_SYNCTHING")' "polish default syncthing right-click should use services.syncthing.service_name"
waybar_test_assert_jq "$clean_sys_polish" '."custom/libredefender"."on-click-right" | test("POLISH_TERM")' "polish default libredefender journalctl should use apps.terminal"
waybar_test_assert_jq "$clean_audio_polish" '."custom/media-prev"."on-click-right" == "playerctl position 41-"' "polish default seek_back_sec not applied"
waybar_test_assert_jq "$clean_audio_polish" '."custom/media-next"."on-click-right" == "playerctl position 42+"' "polish default seek_forward_sec not applied"

echo "PASS: polish default click wiring"
waybar_test_end
