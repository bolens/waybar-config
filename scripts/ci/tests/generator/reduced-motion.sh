#!/usr/bin/env bash
# reduced-motion probe + CSS override (GTK3 has no prefers-reduced-motion).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "reduced-motion"
waybar_test_gen_sandbox

mkdir -p "$TEST_DIR/scripts/lib" "$TEST_DIR/scripts/generate" "$TEST_DIR/theme"
cp "$ROOT_DIR/scripts/lib/reduced-motion-lib.sh" "$TEST_DIR/scripts/lib/"
cp "$ROOT_DIR/scripts/generate/generate-reduced-motion-css.sh" "$TEST_DIR/scripts/generate/"
cp "$ROOT_DIR/scripts/lib/waybar-settings.sh" "$TEST_DIR/scripts/lib/"
chmod +x "$TEST_DIR/scripts/generate/generate-reduced-motion-css.sh"

if ! grep -q 'reduced-motion.generated.css' "$ROOT_DIR/theme.css"; then
  echo "FAIL: theme.css must import reduced-motion.generated.css last" >&2
  fail=1
fi

echo "Testing generate leaves reduced-motion inactive under auto (deterministic)..."
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed" >&2
  fail=1
fi
rm_css="$TEST_DIR/theme/reduced-motion.generated.css"
if [ ! -f "$rm_css" ]; then
  echo "FAIL: reduced-motion.generated.css missing after generate" >&2
  fail=1
fi
if grep -q 'active: true' "$rm_css"; then
  echo "FAIL: generate must not bake host a11y into reduced-motion under auto" >&2
  fail=1
fi
if ! grep -q 'active: false' "$rm_css"; then
  echo "FAIL: expected active: false stub after generate" >&2
  fail=1
fi

echo "Testing force mode emits animation: none override..."
perl -0pi -e 's/"reduced_motion":\s*"[^"]*"/"reduced_motion": "force"/' "$TEST_DIR/data/waybar-settings.jsonc" \
  || perl -0pi -e 's/("idle_glow":\s*(?:true|false))/$1,\n      "reduced_motion": "force"/' "$TEST_DIR/data/waybar-settings.jsonc"
waybar_test_compile_settings
if ! WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  bash "$TEST_DIR/scripts/generate/generate-reduced-motion-css.sh"; then
  echo "FAIL: generate-reduced-motion-css.sh failed under force" >&2
  fail=1
fi
if ! grep -q 'active: true' "$rm_css" || ! grep -q 'animation: none' "$rm_css"; then
  echo "FAIL: force mode should emit active reduced-motion CSS" >&2
  fail=1
fi

echo "Testing env override WAYBAR_REDUCED_MOTION=1..."
perl -0pi -e 's/"reduced_motion":\s*"force"/"reduced_motion": "off"/' "$TEST_DIR/data/waybar-settings.jsonc"
waybar_test_compile_settings
WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" WAYBAR_REDUCED_MOTION=1 \
  bash "$TEST_DIR/scripts/generate/generate-reduced-motion-css.sh"
# generate script forces WAYBAR_REDUCED_MOTION=0 for non-force unless GENERATE_LIVE
# so test the lib apply path directly:
# shellcheck source=/dev/null
. "$TEST_DIR/scripts/lib/reduced-motion-lib.sh"
WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" WAYBAR_REDUCED_MOTION=1 \
  waybar_apply_reduced_motion_css
if ! grep -q 'source: env' "$rm_css"; then
  echo "FAIL: env override should set source: env" >&2
  fail=1
fi

echo "Testing WAYBAR_REDUCED_MOTION=0 wins over force settings..."
WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" WAYBAR_REDUCED_MOTION=0 \
  waybar_apply_reduced_motion_css
# settings still off; env 0 → inactive
if grep -q 'active: true' "$rm_css"; then
  echo "FAIL: env=0 should keep reduced-motion inactive" >&2
  fail=1
fi

echo "Testing GTK CssProvider accepts reduced-motion CSS (skipped if Gtk unavailable)..."
if python3 -c 'import gi; gi.require_version("Gtk","3.0"); from gi.repository import Gtk' >/dev/null 2>&1; then
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" WAYBAR_REDUCED_MOTION=1 \
    waybar_apply_reduced_motion_css
  if ! python3 - "$rm_css" <<'PY'; then
import gi
import sys
from pathlib import Path

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

p = Gtk.CssProvider()
try:
    p.load_from_data(Path(sys.argv[1]).read_bytes())
except Exception as exc:
    print(f"FAIL: Gtk rejected reduced-motion CSS: {exc}", file=sys.stderr)
    sys.exit(1)
print("ok: Gtk accepts reduced-motion CSS")
PY
    fail=1
  fi
else
  echo "note: Gtk.CssProvider probe skipped (PyGObject GTK3 not installed)"
fi

if ! bash -n "$TEST_DIR/scripts/lib/reduced-motion-lib.sh"; then
  echo "FAIL: reduced-motion-lib.sh bash -n" >&2
  fail=1
fi

waybar_test_end
