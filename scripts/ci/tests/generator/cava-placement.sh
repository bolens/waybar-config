#!/usr/bin/env bash
# cava.placement drawer vs inline module order in group/media; cava.enabled strip.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "cava-placement"
waybar_test_gen_sandbox

# Host SoT may disable cava (tooltip safety); force on/off for these checks.
force_cava_enabled() {
  local on="$1"
  python3 - "$TEST_DIR/data/waybar-settings.jsonc" "$on" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
on = sys.argv[2].lower() in ("1", "true", "yes")
text = path.read_text()
if re.search(r'"cava"\s*:\s*\{[^}]*"enabled"\s*:', text, re.S):
  text = re.sub(
    r'("cava"\s*:\s*\{[^}]*?"enabled"\s*:\s*)(true|false)',
    rf'\1{"true" if on else "false"}',
    text,
    count=1,
    flags=re.S,
  )
else:
  text = re.sub(
    r'("cava"\s*:\s*\{)',
    rf'\1\n    "enabled": {"true" if on else "false"},',
    text,
    count=1,
  )
path.write_text(text)
PY
  waybar_test_compile_settings
}

echo "Testing cava.placement drawer (default) order..."
force_cava_enabled true
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

echo "Testing cava.enabled=false strips custom/cava from media group..."
force_cava_enabled false
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed for cava.enabled=false" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '(."group/media".modules | index("custom/cava")) == null' \
  "enabled=false: custom/cava must be absent from group/media"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/drawers.generated.jsonc" \
  '(."custom/media-drawer"."tooltip-format" | test("Visualizer")) | not' \
  "enabled=false: media-drawer tooltip should omit Visualizer"

echo "PASS: cava placement order differences"
waybar_test_end
