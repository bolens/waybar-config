#!/usr/bin/env bash
# animations.generated.css keyframes present/absent per visual.animations flags.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "animations-css"
waybar_test_gen_sandbox

echo "Testing animations CSS defaults (pulse+breathe on, idle_glow off)..."
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before animations-css checks" >&2
  fail=1
fi

anim="$TEST_DIR/theme/animations.generated.css"
# Emitted by scripts/generate/generate-animations-css.sh from visual.animations.*.
if [ ! -f "$anim" ]; then
  echo "FAIL: theme/animations.generated.css missing after generate (see generate-animations-css.sh)" >&2
  fail=1
fi
if ! grep -q 'waybar-workspace-pulse' "$anim"; then
  echo "FAIL: expected workspace_pulse keyframes (visual.animations.workspace_pulse → generate-animations-css.sh)" >&2
  fail=1
fi
if ! grep -q 'waybar-critical-breathe' "$anim"; then
  echo "FAIL: expected critical_breathe keyframes (visual.animations.critical_breathe → generate-animations-css.sh)" >&2
  fail=1
fi
# GTK3: multi-percentage keyframe selectors crash Waybar (use from/to + alternate).
if grep -E '^[[:space:]]*[0-9]+%[[:space:]]*,[[:space:]]*[0-9]+%' "$anim"; then
  echo "FAIL: animations.generated.css multi-percentage keyframes are not GTK3-safe (fix generate-animations-css.sh)" >&2
  fail=1
fi
if ! grep -qE '^[[:space:]]*(from|to)[[:space:]]*\{' "$anim"; then
  echo "FAIL: expected from/to keyframes for GTK3 compatibility (generate-animations-css.sh)" >&2
  fail=1
fi
if grep -q 'waybar-idle-glow' "$anim"; then
  echo "FAIL: idle_glow should be absent when visual.animations.idle_glow is false" >&2
  fail=1
fi
if ! grep -q 'animations.generated.css' "$TEST_DIR/../" 2>/dev/null; then
  :
fi
# theme.css import lives in repo root copy; check sandbox scripts generated file + source SoT
if ! grep -q 'theme/animations.generated.css' "$ROOT_DIR/theme.css"; then
  echo "FAIL: theme.css should import theme/animations.generated.css" >&2
  fail=1
fi

if [ ! -x "$TEST_DIR/scripts/generate/generate-animations-css.sh" ] \
  && [ ! -f "$TEST_DIR/scripts/generate/generate-animations-css.sh" ]; then
  echo "FAIL: generate-animations-css.sh missing" >&2
  fail=1
fi
if ! bash -n "$TEST_DIR/scripts/generate/generate-animations-css.sh"; then
  echo "FAIL: generate-animations-css.sh failed bash -n" >&2
  fail=1
fi

echo "Testing all animation flags enabled..."
perl -0pi -e 's/"idle_glow":\s*false/"idle_glow": true/' "$TEST_DIR/data/waybar-settings.jsonc"
waybar_test_compile_settings
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed with idle_glow enabled" >&2
  fail=1
fi
if ! grep -q 'waybar-idle-glow' "$TEST_DIR/theme/animations.generated.css"; then
  echo "FAIL: expected idle_glow keyframes when visual.animations.idle_glow is true (generate-animations-css.sh)" >&2
  fail=1
fi

echo "Testing all animation flags disabled..."
perl -0pi -e 's/"workspace_pulse":\s*true/"workspace_pulse": false/; s/"critical_breathe":\s*true/"critical_breathe": false/; s/"idle_glow":\s*true/"idle_glow": false/' \
  "$TEST_DIR/data/waybar-settings.jsonc"
waybar_test_compile_settings
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed with animations disabled" >&2
  fail=1
fi
if grep -qE 'waybar-workspace-pulse|waybar-critical-breathe|waybar-idle-glow' "$TEST_DIR/theme/animations.generated.css"; then
  echo "FAIL: no keyframes expected when all visual.animations flags are false" >&2
  fail=1
fi

echo "PASS: animations CSS"
waybar_test_end
