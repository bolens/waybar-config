#!/usr/bin/env bash
# cava.placement drawer vs inline module order in group/media.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "cava-placement"
waybar_test_gen_sandbox

echo "Testing cava.placement drawer (default) order..."
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed for default cava placement" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '."group/media".modules[0] == "custom/media-drawer"' \
  "drawer placement: media-drawer should be first"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '."group/media".modules[1] == "custom/cava"' \
  "drawer placement: cava should follow media-drawer"
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" \
  '.cava.placement == "drawer"' \
  "default cava.placement should be drawer"

echo "Testing cava.placement=inline (cava as always-visible head)..."
# Edit jsonc source (comments-safe) then recompile.
perl -0pi -e 's/"placement":\s*"drawer"/"placement": "inline"/' "$TEST_DIR/data/waybar-settings.jsonc"
waybar_test_compile_settings
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" \
  '.cava.placement == "inline"' \
  "compiled settings should reflect inline placement"
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed for inline cava placement" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '."group/media".modules[0] == "custom/cava"' \
  "inline placement: cava should be first (always-visible drawer head)"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '."group/media".modules | index("custom/media-drawer") == 1' \
  "inline placement: media-drawer should follow cava"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '(."group/media".modules | map(select(. == "custom/cava")) | length) == 1' \
  "inline placement: cava should appear exactly once"

echo "PASS: cava placement order differences"
waybar_test_end
