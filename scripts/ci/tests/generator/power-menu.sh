#!/usr/bin/env bash
# Power menu module wiring + rofi grid action.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "power-menu"
waybar_test_gen_sandbox

echo "Testing power-menu wiring and power-click.sh menu..."
cp "$ROOT_DIR/scripts/system/power-click.sh" "$TEST_DIR/scripts/system/"
chmod +x "$TEST_DIR/scripts/system/power-click.sh"
if ! waybar_test_gen_modules; then
  echo "FAIL: generate failed before power-menu checks" >&2
  fail=1
fi

waybar_test_assert_json_file_jq "$TEST_DIR/modules/utilities.generated.jsonc" \
  '."custom/power-menu"."on-click" | test("power-click\\.sh menu")' \
  "custom/power-menu should call power-click.sh menu"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/groups.generated.jsonc" \
  '."group/power".modules | index("custom/power-menu")' \
  "custom/power-menu missing from group/power"
waybar_test_assert_json_file_jq "$TEST_DIR/modules/drawers.generated.jsonc" \
  '."custom/power-drawer"."tooltip-format" | test("Power menu")' \
  "power-drawer tooltip should list Power menu"

if ! bash -n "$TEST_DIR/scripts/system/power-click.sh"; then
  echo "FAIL: power-click.sh failed bash -n" >&2
  fail=1
fi

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/cache"
waybar_test_write_bin_stub rofi <<'EOF'
#!/usr/bin/env sh
printf 'rofi %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
# Pick Lock (no confirm dialog)
printf '  Lock\n'
EOF
waybar_test_write_bin_stub loginctl <<'EOF'
#!/usr/bin/env sh
printf 'loginctl %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
EOF
: >"$TEST_DIR/bin/calls.log"
chmod +x "$TEST_DIR/bin/"*

PATH="$TEST_DIR/bin:/usr/bin:/bin" \
  WAYBAR_HOME="$TEST_DIR" \
  WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_COMPOSITOR=kde \
  "$TEST_DIR/scripts/system/power-click.sh" menu

if ! grep -q 'loginctl lock-session' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: power menu Lock should call loginctl lock-session. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi
if ! grep -q '^rofi ' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: power menu should invoke rofi. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

# Suspend path requires confirm Yes
waybar_test_write_bin_stub rofi <<'EOF'
#!/usr/bin/env sh
printf 'rofi %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
if printf '%s' "$*" | grep -q 'Confirm'; then
  printf 'Yes, suspend\n'
else
  printf '󰤄  Suspend\n'
fi
EOF
waybar_test_write_bin_stub systemctl <<'EOF'
#!/usr/bin/env sh
printf 'systemctl %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
EOF
: >"$TEST_DIR/bin/calls.log"
PATH="$TEST_DIR/bin:/usr/bin:/bin" \
  WAYBAR_HOME="$TEST_DIR" \
  WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_COMPOSITOR=kde \
  "$TEST_DIR/scripts/system/power-click.sh" menu

if ! grep -q 'systemctl suspend' "$TEST_DIR/bin/calls.log"; then
  echo "FAIL: power menu Suspend should call systemctl suspend. log=$(cat "$TEST_DIR/bin/calls.log")" >&2
  fail=1
fi

waybar_test_end
