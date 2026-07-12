#!/usr/bin/env bash
# Plasma keyboard-layout must use getLayout/getLayoutsList — not removed getCurrentLayout.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "keyboard-layout-plasma"
waybar_test_gen_sandbox

status="$TEST_DIR/scripts/system/keyboard-layout-status.sh"
if [ ! -x "$status" ]; then
  echo "FAIL: keyboard-layout-status.sh missing" >&2
  fail=1
  waybar_test_end
fi

# Guard: must not call removed Plasma layout getter (produces SIGNATURE '' labels).
if grep -E 'KeyboardLayouts\.getCurrentLayout|org\.kde\.KeyboardLayouts\.getCurrentLayout' "$status"; then
  echo "FAIL: keyboard-layout-status.sh still calls removed getCurrentLayout" >&2
  fail=1
fi
if ! grep -q 'getLayoutsList' "$status" || ! grep -q 'KeyboardLayouts.getLayout' "$status"; then
  echo "FAIL: keyboard-layout-status.sh must use getLayout + getLayoutsList" >&2
  fail=1
fi

stub_bin=$(mktemp -d)
cat >"$stub_bin/qdbus6" <<'EOF'
#!/bin/sh
# Mimic Plasma KeyboardLayouts: getLayout → 0; getLayoutsList --literal → one (sss).
case "$*" in
  *getLayout)
    echo 0
    ;;
  *--literal*getLayoutsList* | *getLayoutsList*--literal*)
    echo '[Argument: a(sss) {[Argument: (sss) "us", "", "English (US)"]}]'
    ;;
  *getLayoutsList*)
    echo '[Argument: a(sss) {[Argument: (sss) "us", "", "English (US)"]}]'
    ;;
  *getCurrentLayout*)
    echo "Error: org.freedesktop.DBus.Error.UnknownMethod" >&2
    echo "No such method 'getCurrentLayout' in interface 'org.kde.KeyboardLayouts' at object path '/Layouts' (signature '')" >&2
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$stub_bin/qdbus6"

# Force KDE compositor detection.
out=$(
  PATH="$stub_bin:$PATH" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    XDG_CURRENT_DESKTOP=KDE \
    WAYBAR_COMPOSITOR=kde \
    "$status" 2>/dev/null || true
)

waybar_test_assert_jq "$out" \
  '(.text | test("SIGNATURE"; "i") | not) and (.text | test("\\?\\?") | not) and (.text | length) > 0' \
  "keyboard-layout must not emit SIGNATURE/?? from Plasma stubs: $out"

waybar_test_assert_jq "$out" \
  '.text == "US" and (.tooltip | test("English \\(US\\)")) and (.class == "us")' \
  "keyboard-layout Plasma stub expected US / English (US): $out"

echo "Testing DBus error text is never used as the layout label..."
cat >"$stub_bin/qdbus6" <<'EOF'
#!/bin/sh
# Simulate old/broken getter returning an error string on stdout.
case "$*" in
  *getLayout)
    echo "Error: org.freedesktop.DBus.Error.UnknownMethod"
    echo "No such method 'getCurrentLayout' in interface 'org.kde.KeyboardLayouts' at object path '/Layouts' (signature '')"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$stub_bin/qdbus6"
bad_out=$(
  PATH="$stub_bin:$PATH" \
    WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
    WAYBAR_COMPOSITOR=kde \
    "$status" 2>/dev/null || true
)
waybar_test_assert_jq "$bad_out" \
  '(.text | test("SIGNATURE"; "i") | not) and (.text == "??")' \
  "keyboard-layout must map DBus error blobs to ?? not SIGNATURE: $bad_out"

rm -rf "$stub_bin"
echo "PASS: keyboard-layout-plasma"
waybar_test_end
