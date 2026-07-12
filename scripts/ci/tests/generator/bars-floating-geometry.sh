#!/usr/bin/env bash
# Floating island geometry + glass/chrome token overrides.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "bars-floating-geometry"
waybar_test_gen_sandbox
waybar_test_compile_settings
mv "$TEST_DIR/data/waybar-settings.jsonc" "$TEST_DIR/data/waybar-settings.jsonc.bak"

settings_json="$TEST_DIR/data/waybar-settings.json"
css_tokens="$TEST_DIR/theme/tokens.generated.css"

echo "Testing floating=true → exclusive false + margins in bar-defaults..."
tmp=$(mktemp)
jq '
  .bars.floating = true
  | .bars.margin_top = 9
  | .bars.margin_right = 13
  | .bars.margin_bottom = 2
  | .bars.margin_left = 14
  | .bars.glass_opacity = 0.55
  | .bars.chrome_radius = 16
' "$settings_json" >"$tmp"
mv "$tmp" "$settings_json"

# generate-settings reads compiled JSON; keep jsonc from overwriting our knobs.
if ! WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  bash "$TEST_DIR/scripts/generate/generate-settings.sh" >/dev/null; then
  echo "FAIL: generate-settings failed with floating geometry" >&2
  exit 1
fi

clean_bar=$(waybar_test_read_jsonc "$TEST_DIR/includes/bar-defaults.generated.jsonc")
waybar_test_assert_jq "$clean_bar" '.exclusive == false' "floating true should set exclusive false"
waybar_test_assert_jq "$clean_bar" '."margin-top" == 9' "floating margin-top not applied"
waybar_test_assert_jq "$clean_bar" '."margin-right" == 13' "floating margin-right not applied"
waybar_test_assert_jq "$clean_bar" '."margin-bottom" == 2' "floating margin-bottom not applied"
waybar_test_assert_jq "$clean_bar" '."margin-left" == 14' "floating margin-left not applied"
if echo "$clean_bar" | jq -e 'has("floating") or has("glass_opacity") or has("chrome_radius") or has("margin_top")' >/dev/null 2>&1; then
  echo "FAIL: floating/glass settings keys leaked into bar-defaults" >&2
  fail=1
fi

echo "Testing glass_opacity / chrome_radius affect tokens..."
WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  bash "$TEST_DIR/scripts/generate/generate-theme-tokens.sh"
if [ ! -f "$css_tokens" ]; then
  echo "FAIL: tokens.generated.css missing after floating generate" >&2
  fail=1
else
  if ! grep -q 'border-radius: 16px' "$css_tokens"; then
    echo "FAIL: chrome_radius 16 not applied in tokens" >&2
    fail=1
  fi
  if ! grep -qE 'background: rgba\([^)]+, 0\.55\)' "$css_tokens"; then
    echo "FAIL: glass_opacity 0.55 not rewritten into window#waybar background" >&2
    fail=1
  fi
  if ! grep -A5 'window#waybar {' "$css_tokens" | grep -q 'border: 1px solid'; then
    echo "FAIL: floating mode should use full border on window#waybar" >&2
    fail=1
  fi
fi

echo "Testing floating=false restores exclusive without margins..."
tmp=$(mktemp)
jq '
  .bars.floating = false
  | .bars.glass_opacity = null
  | .bars.chrome_radius = null
' "$settings_json" >"$tmp"
mv "$tmp" "$settings_json"

if ! WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  bash "$TEST_DIR/scripts/generate/generate-settings.sh" >/dev/null; then
  echo "FAIL: generate-settings failed after restoring floating=false" >&2
  exit 1
fi
clean_bar=$(waybar_test_read_jsonc "$TEST_DIR/includes/bar-defaults.generated.jsonc")
waybar_test_assert_jq "$clean_bar" '.exclusive == true' "floating false should keep exclusive true"
if echo "$clean_bar" | jq -e 'has("margin-top") or has("margin-left")' >/dev/null 2>&1; then
  echo "FAIL: non-floating bar-defaults should not include margin-* keys" >&2
  fail=1
fi

echo "PASS: bars-floating-geometry checks"
waybar_test_end
