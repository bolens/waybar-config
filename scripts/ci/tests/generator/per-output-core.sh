#!/usr/bin/env bash
# output-lib list/sanitize + workspace scroll sources output-lib (1/2/4 fixture names).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "per-output-core"
waybar_test_gen_sandbox

# Hide real compositor probes so WAYBAR_TEST_OUTPUTS is used.
export PATH="/usr/bin:/bin"

lib="$TEST_DIR/scripts/lib/output-lib.sh"
# shellcheck source=/dev/null
. "$lib"

assert_list_count() {
  local csv="$1"
  local expect="$2"
  local label="$3"
  got=$(WAYBAR_TEST_OUTPUTS="$csv" waybar_list_outputs | sed '/^$/d' | wc -l | tr -d ' ')
  if [ "$got" -ne "$expect" ]; then
    echo "FAIL: $label — expected $expect outputs from '$csv', got $got" >&2
    WAYBAR_TEST_OUTPUTS="$csv" waybar_list_outputs >&2 || true
    fail=1
    return 0
  fi
  echo "PASS: list $label ($expect)"
}

assert_list_count "OUTA" 1 "1-monitor fixture"
assert_list_count "OUTA,OUTB" 2 "2-monitor fixture"
assert_list_count "1,2,4,X" 4 "4-monitor fixture names 1,2,4,X"

# Sanitize
safe=$(waybar_css_class_for_output "DP-1")
[ "$safe" = "DP-1" ] || {
  echo "FAIL: sanitize DP-1 → $safe" >&2
  fail=1
}
safe2=$(waybar_css_class_for_output "HDMI A:1")
case "$safe2" in
  *[!A-Za-z0-9_-]*)
    echo "FAIL: sanitize left unsafe chars: $safe2" >&2
    fail=1
    ;;
  *)
    echo "PASS: sanitize HDMI A:1 → $safe2"
    ;;
esac

# Fixture names from the suite brief
for name in 1 2 4; do
  s=$(waybar_css_class_for_output "$name")
  [ -n "$s" ] || {
    echo "FAIL: empty sanitize for '$name'" >&2
    fail=1
  }
done
echo "PASS: sanitize fixture names 1,2,4"

# workspaces-click.sh must source output-lib
click="$TEST_DIR/scripts/workspaces/workspaces-click.sh"
if ! grep -Fq 'output-lib.sh' "$click"; then
  echo "FAIL: workspaces-click.sh does not source output-lib.sh" >&2
  fail=1
else
  echo "PASS: workspaces-click.sh sources output-lib"
fi

if ! grep -Fq 'waybar_scroll_per_output_enabled' "$click"; then
  echo "FAIL: workspaces-click.sh missing waybar_scroll_per_output_enabled" >&2
  fail=1
else
  echo "PASS: workspaces-click.sh uses scroll_per_output helper"
fi

# scroll_per_output default true
if ! waybar_scroll_per_output_enabled; then
  echo "FAIL: scroll_per_output should default enabled" >&2
  fail=1
else
  echo "PASS: scroll_per_output enabled by default"
fi

waybar_test_end
