#!/usr/bin/env bash
# icons.appicon CSS generator contracts (dock PNG proof via appicon CLI).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "dock-appicon-css"
waybar_test_gen_sandbox

css="$TEST_DIR/theme/dock-appicons.generated.css"

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

waybar_test_patch_settings '.icons.appicon.enabled = true | .icons.appicon.size = 28'
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
if ! grep -q 'url("dock-appicons/browser")' "$css"; then
  echo "FAIL: expected browser dock-appicon CSS rule" >&2
  exit 1
fi
if ! grep -q '#dock-apps label.appicon' "$css"; then
  echo "FAIL: expected shared label.appicon rules" >&2
  exit 1
fi
if ! grep -q 'font-size: 0' "$ROOT_DIR/user-style/dock.css"; then
  echo "FAIL: user-style/dock.css must collapse glyph metrics for label.appicon" >&2
  exit 1
fi
if ! grep -q ':not(\.appicon)' "$ROOT_DIR/theme/accents/dock.css"; then
  echo "FAIL: accents/dock.css must skip .appicon for glyph color/hover" >&2
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

if ! grep -q 'theme/dock-appicons.generated.css' "$ROOT_DIR/theme.css"; then
  echo "FAIL: theme.css must import theme/dock-appicons.generated.css" >&2
  exit 1
fi

if git -C "$ROOT_DIR" check-ignore -q --no-index theme/dock-appicons.generated.css; then
  echo "FAIL: theme/dock-appicons.generated.css must NOT be gitignored" >&2
  exit 1
fi
if ! git -C "$ROOT_DIR" check-ignore -q --no-index theme/dock-appicons/browser; then
  echo "FAIL: theme/dock-appicons/* runtime symlinks must be gitignored" >&2
  exit 1
fi

if [ ! -x "$TEST_DIR/scripts/infra/install-appicon.sh" ]; then
  echo "FAIL: install-appicon.sh missing or not executable" >&2
  exit 1
fi
waybar_test_assert_bash_n "$TEST_DIR/scripts/infra/install-appicon.sh" \
  "install-appicon.sh failed bash -n"
if ! grep -q 'APPICON_VERSION' "$TEST_DIR/scripts/infra/install-appicon.sh"; then
  echo "FAIL: install-appicon.sh must pin APPICON_VERSION" >&2
  exit 1
fi
if ! grep -q 'sha256' "$TEST_DIR/scripts/infra/install-appicon.sh"; then
  echo "FAIL: install-appicon.sh must verify SHA256" >&2
  exit 1
fi

waybar_test_end
