#!/usr/bin/env bash
# capture-lib helpers + XDG/env portability.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "capture-lib"
waybar_test_secrets_sandbox

echo "Testing capture-lib settings helpers..."
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/capture-lib.sh"
  shot=$(capture_screenshot_base_dir)
  rec=$(capture_screenrecord_base_dir)
  fps=$(capture_screenrecord_fps)
  if [[ "$shot" != "/tmp/wb-shots" || "$rec" != "/tmp/wb-recs" || "$fps" != "42" ]]; then
    echo "FAIL: capture-lib helpers wrong: shot=$shot rec=$rec fps=$fps" >&2
    exit 1
  fi
  export WAYBAR_SCREENREC_FPS=99
  fps2=$(capture_screenrecord_fps)
  if [[ "$fps2" != "99" ]]; then
    echo "FAIL: WAYBAR_SCREENREC_FPS override ignored (got: $fps2)" >&2
    exit 1
  fi
) || fail=1
echo "PASS: capture-lib helpers"

# Portable XDG defaults when capture dirs are null + env overrides
echo "Testing capture-lib XDG / env portability..."
cp "$TEST_DIR/data/waybar-settings.jsonc" "$TEST_DIR/data/waybar-settings.jsonc.bak"
(
  cat >"$TEST_DIR/data/waybar-settings.jsonc" <<'JSON'
{
  "capture": {
    "screenshot_dir": null,
    "screenrecord_dir": null,
    "screenrecord_fps": 30
  }
}
JSON
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/capture-lib.sh"
  export HOME="$TEST_DIR/fakehome"
  export XDG_PICTURES_DIR="$TEST_DIR/Pictures"
  export XDG_VIDEOS_DIR="$TEST_DIR/Videos"
  unset WAYBAR_SCREENSHOT_DIR WAYBAR_SCREENRECORD_DIR
  shot=$(capture_screenshot_base_dir)
  rec=$(capture_screenrecord_base_dir)
  if [ "$shot" != "$TEST_DIR/Pictures/Screenshots" ] || [ "$rec" != "$TEST_DIR/Videos/Screenrecordings" ]; then
    echo "FAIL: XDG capture defaults: shot=$shot rec=$rec" >&2
    exit 1
  fi
  export WAYBAR_SCREENSHOT_DIR="/env/shots"
  export WAYBAR_SCREENRECORD_DIR="/env/recs"
  shot2=$(capture_screenshot_base_dir)
  rec2=$(capture_screenrecord_base_dir)
  if [ "$shot2" != "/env/shots" ] || [ "$rec2" != "/env/recs" ]; then
    echo "FAIL: capture env overrides: shot=$shot2 rec=$rec2" >&2
    exit 1
  fi
) || fail=1
mv -f "$TEST_DIR/data/waybar-settings.jsonc.bak" "$TEST_DIR/data/waybar-settings.jsonc"
waybar_test_compile_settings
echo "PASS: capture-lib XDG / env portability"

waybar_test_end
