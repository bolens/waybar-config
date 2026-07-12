#!/usr/bin/env bash
# Theme mode pipeline: static / preset merge / wallpaper import / invalid soft-fail.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "theme-mode-pipeline"
waybar_test_gen_sandbox
# Compile SoT once; mutate compiled JSON for mode tests (avoid ambiguous "mode" keys in jsonc).
waybar_test_compile_settings
# Hide jsonc so sourcing waybar-settings.sh does not overwrite our JSON mutations.
mv "$TEST_DIR/data/waybar-settings.jsonc" "$TEST_DIR/data/waybar-settings.jsonc.bak"

css_tokens="$TEST_DIR/theme/tokens.generated.css"
settings_json="$TEST_DIR/data/waybar-settings.json"

set_theme() {
  local mode="$1"
  local preset="${2:-}"
  local tmp
  tmp=$(mktemp)
  if [ -n "$preset" ]; then
    jq --arg m "$mode" --arg p "$preset" '.theme.mode = $m | .theme.preset = $p' \
      "$settings_json" >"$tmp"
  else
    jq --arg m "$mode" '.theme.mode = $m' "$settings_json" >"$tmp"
  fi
  mv "$tmp" "$settings_json"
  WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    bash "$TEST_DIR/scripts/generate/generate-theme-tokens.sh"
}

echo "Testing static theme mode (no wallpaper import)..."
set_theme "static"
if [ ! -f "$css_tokens" ]; then
  echo "FAIL: tokens.generated.css missing after static generate" >&2
  fail=1
elif grep -q 'tokens.wallpaper.generated.css' "$css_tokens"; then
  echo "FAIL: static mode should not @import wallpaper tokens" >&2
  fail=1
fi

echo "Testing preset=nord merges nord colors into tokens..."
# Clear theme.colors so preset pack is visible (settings keys override preset when set).
tmp=$(mktemp)
jq '.theme.mode = "preset" | .theme.preset = "nord" | .theme.colors = {}' \
  "$settings_json" >"$tmp"
mv "$tmp" "$settings_json"
WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  bash "$TEST_DIR/scripts/generate/generate-theme-tokens.sh"
if [ ! -f "$css_tokens" ]; then
  echo "FAIL: tokens.generated.css missing after preset generate" >&2
  fail=1
else
  if ! grep -q 'background: rgba(46, 52, 64, 0.92)' "$css_tokens"; then
    echo "FAIL: nord background not merged into tokens" >&2
    fail=1
  fi
  if ! grep -q 'color: #d8dee9' "$css_tokens"; then
    echo "FAIL: nord foreground not merged into tokens" >&2
    fail=1
  fi
  if ! grep -q 'background: #2e3440' "$css_tokens"; then
    echo "FAIL: nord tooltip_background not merged into tokens" >&2
    fail=1
  fi
  if grep -q 'tokens.wallpaper.generated.css' "$css_tokens"; then
    echo "FAIL: preset mode should not @import wallpaper tokens" >&2
    fail=1
  fi
fi
# Sparse settings override wins over preset
tmp=$(mktemp)
jq '.theme.mode = "preset" | .theme.preset = "nord" | .theme.colors = {"foreground": "#ff00aa"}' \
  "$settings_json" >"$tmp"
mv "$tmp" "$settings_json"
WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  bash "$TEST_DIR/scripts/generate/generate-theme-tokens.sh"
if ! grep -q 'color: #ff00aa' "$css_tokens"; then
  echo "FAIL: settings theme.colors override should win over nord preset" >&2
  fail=1
fi
if ! grep -q 'background: rgba(46, 52, 64, 0.92)' "$css_tokens"; then
  echo "FAIL: nord background should remain when only foreground overridden" >&2
  fail=1
fi

echo "Testing wallpaper mode adds @import tokens.wallpaper.generated.css..."
set_theme "wallpaper"
if [ ! -f "$css_tokens" ]; then
  echo "FAIL: tokens.generated.css missing after wallpaper generate" >&2
  fail=1
elif ! grep -q '@import "tokens.wallpaper.generated.css"' "$css_tokens"; then
  echo "FAIL: wallpaper mode missing @import tokens.wallpaper.generated.css" >&2
  fail=1
fi
if [ ! -f "$TEST_DIR/theme/tokens.wallpaper.generated.css" ]; then
  echo "FAIL: wallpaper stub tokens.wallpaper.generated.css was not created" >&2
  fail=1
fi

echo "Testing invalid mode fails soft (treat as static)..."
set_theme "not-a-real-mode"
if [ ! -f "$css_tokens" ]; then
  echo "FAIL: tokens.generated.css missing after invalid mode" >&2
  fail=1
elif grep -q 'tokens.wallpaper.generated.css' "$css_tokens"; then
  echo "FAIL: invalid mode should soft-fail to static (no wallpaper import)" >&2
  fail=1
fi
if ! grep -q 'window#waybar' "$css_tokens"; then
  echo "FAIL: invalid mode should still emit window#waybar tokens" >&2
  fail=1
fi

echo "PASS: theme-mode-pipeline checks"
waybar_test_end
