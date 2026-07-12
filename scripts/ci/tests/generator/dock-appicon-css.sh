#!/usr/bin/env bash
# icons.appicon CSS generator contracts (dock PNG proof via appicon CLI).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "dock-appicon-css"
waybar_test_gen_sandbox

css="$TEST_DIR/theme/dock-appicons.generated.css"
semantic="$TEST_DIR/theme/semantic-colors.generated.css"

waybar_test_patch_settings '.icons.appicon.enabled = false'
if ! waybar_test_gen_default; then
  echo "FAIL: generate failed before dock-appicon checks" >&2
  exit 1
fi
if [ ! -f "$css" ]; then
  echo "FAIL: dock-appicons.generated.css missing when icons.appicon disabled" >&2
  exit 1
fi
if ! grep -q 'icons.appicon disabled' "$css"; then
  echo "FAIL: disabled dock-appicons.generated.css should be a stub" >&2
  exit 1
fi

waybar_test_patch_settings \
  '.icons.appicon.enabled = true | .icons.appicon.size = 28 | .icons.appicon.gap = 12 | .icons.appicon.pad = 8'
if ! waybar_test_gen_default; then
  echo "FAIL: generate failed with icons.appicon enabled" >&2
  exit 1
fi
if [ ! -f "$css" ]; then
  echo "FAIL: dock-appicons.generated.css missing when icons.appicon enabled" >&2
  exit 1
fi
if ! grep -q 'min-width: 28px' "$css"; then
  echo "FAIL: dock-appicons.generated.css should use icons.appicon.size" >&2
  exit 1
fi
if ! grep -q 'background-size: 28px 28px' "$css"; then
  echo "FAIL: dock-appicons.generated.css should set exact background-size" >&2
  exit 1
fi
if ! grep -q 'margin-right: 12px' "$css"; then
  echo "FAIL: dock-appicons.generated.css should use icons.appicon.gap" >&2
  exit 1
fi
if ! grep -q 'padding: 8px' "$css"; then
  echo "FAIL: dock-appicons.generated.css should use icons.appicon.pad on all sides" >&2
  exit 1
fi
# Layout must apply without .appicon so glyph fallbacks keep the same gaps.
if ! grep -qE '^#custom-dock-[a-z0-9-]+,' "$css"; then
  echo "FAIL: expected shared #custom-dock-* layout rules without requiring .appicon" >&2
  exit 1
fi
if ! grep -q 'url("file://.*/theme/dock-appicons/browser.png")' "$css"; then
  echo "FAIL: expected file:// browser.png dock-appicon CSS rule" >&2
  exit 1
fi
if ! grep -q '#custom-dock-browser.appicon:hover' "$css"; then
  echo "FAIL: expected hover rules that keep background-image" >&2
  exit 1
fi
if ! grep -q ':not(\.appicon)' "$ROOT_DIR/theme/accents/dock.css"; then
  echo "FAIL: accents/dock.css must skip .appicon for glyph color/hover" >&2
  exit 1
fi

# Pill hover must use background-color (not background shorthand) or icons vanish.
if [ -f "$semantic" ]; then
  if grep -E '^[[:space:]]*background:' "$semantic" | grep -q '0\.12\|pill'; then
    :
  fi
  if ! grep -q 'background-color:' "$semantic"; then
    echo "FAIL: semantic-colors.generated.css must use background-color for pills" >&2
    exit 1
  fi
  # The hover block should not use background shorthand next to box-shadow pill glow.
  hover_block="$(tr '\n' ' ' <"$semantic" | grep -oE '\{[^}]*box-shadow: 0 0 10px[^}]*\}' | head -1 || true)"
  if printf '%s' "$hover_block" | grep -qE '[[:space:]]background:'; then
    echo "FAIL: pill hover must not use background shorthand (wipes background-image)" >&2
    exit 1
  fi
fi

theme_css="$ROOT_DIR/theme.css"
sem_line="$(grep -n 'semantic-colors.generated.css' "$theme_css" | head -1 | cut -d: -f1)"
icon_line="$(grep -n 'dock-appicons.generated.css' "$theme_css" | head -1 | cut -d: -f1)"
if [ -z "$sem_line" ] || [ -z "$icon_line" ] || [ "$icon_line" -le "$sem_line" ]; then
  echo "FAIL: theme.css must import dock-appicons.generated.css after semantic-colors" >&2
  exit 1
fi

if [ ! -x "$TEST_DIR/scripts/dock/dock-appicon-prefetch.sh" ]; then
  echo "FAIL: dock-appicon-prefetch.sh missing or not executable" >&2
  exit 1
fi
waybar_test_assert_bash_n "$TEST_DIR/scripts/dock/dock-appicon-prefetch.sh" \
  "dock-appicon-prefetch.sh failed bash -n"
if [ ! -f "$TEST_DIR/scripts/lib/appicon-lib.sh" ]; then
  echo "FAIL: appicon-lib.sh missing" >&2
  exit 1
fi

if git -C "$ROOT_DIR" check-ignore -q --no-index theme/dock-appicons.generated.css; then
  echo "FAIL: theme/dock-appicons.generated.css must NOT be gitignored" >&2
  exit 1
fi
if ! git -C "$ROOT_DIR" check-ignore -q --no-index theme/dock-appicons/browser.png; then
  echo "FAIL: theme/dock-appicons/*.png must be gitignored" >&2
  exit 1
fi

if [ ! -x "$TEST_DIR/scripts/infra/install-appicon.sh" ]; then
  echo "FAIL: install-appicon.sh missing or not executable" >&2
  exit 1
fi
waybar_test_assert_bash_n "$TEST_DIR/scripts/infra/install-appicon.sh" \
  "install-appicon.sh failed bash -n"

waybar_test_end
