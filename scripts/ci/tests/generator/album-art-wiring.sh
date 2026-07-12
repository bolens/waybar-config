#!/usr/bin/env bash
# Album art module present/absent and hide-empty wiring.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "album-art-wiring"
waybar_test_gen_sandbox

echo "Testing album art disabled..."
# Hermetic: force-disable regardless of SoT default.
waybar_test_patch_settings '.visual.album_art.enabled = false'
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before album-art checks" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/audio.generated.jsonc" \
  'has("custom/album-art") | not' \
  "custom/album-art should be absent when visual.album_art.enabled=false"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '."group/media".modules | index("custom/album-art") | not' \
  "album-art should not appear in group/media when disabled"

if [ ! -x "$TEST_DIR/scripts/media/album-art-status.sh" ]; then
  echo "FAIL: album-art-status.sh missing or not executable" >&2
  fail=1
fi
waybar_test_assert_bash_n "$TEST_DIR/scripts/media/album-art-status.sh" \
  "album-art-status.sh failed bash -n"

echo "Testing album art enabled..."
waybar_test_patch_settings '.visual.album_art.enabled = true'
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed with album_art enabled" >&2
  fail=1
fi
waybar_test_assert_json_file_jq "$TEST_DIR/modules/audio.generated.jsonc" \
  '."custom/album-art"."hide-empty-text" == true' \
  "custom/album-art should set hide-empty-text"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/audio.generated.jsonc" \
  '."custom/album-art".exec | test("media/album-art-status\\.sh$")' \
  "custom/album-art exec should point at album-art-status.sh"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '
    (."group/media".modules | index("custom/album-art")) as $a
    | (."group/media".modules | index("custom/mpris")) as $m
    | ($a != null) and ($m != null) and ($a < $m)
  ' \
  "album-art should be inserted before mpris in group/media"

ART_CACHE=$(mktemp -d)
STUB_BIN=$(mktemp -d)
# Hermetic: never talk to the host's real MPRIS players via playerctl.
cat >"$STUB_BIN/playerctl" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$STUB_BIN/playerctl"
hidden=$(
  XDG_CACHE_HOME="$ART_CACHE" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    PATH="$STUB_BIN:/usr/bin:/bin" \
    "$TEST_DIR/scripts/media/album-art-status.sh" 2>/dev/null || true
)
waybar_test_assert_jq "$hidden" \
  '.class == "hidden" and .text == ""' \
  "album-art without playerctl/player should hide: $hidden"
rm -rf "$ART_CACHE" "$STUB_BIN"

echo "PASS: album art wiring"
waybar_test_end
