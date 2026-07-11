#!/usr/bin/env bash
# Lifecycle helpers for modular CI suites (sourced via waybar-test-harness.sh).

# shellcheck source=../waybar-test-sanitize-env.sh
. "${WAYBAR_TEST_ROOT:-${ROOT_DIR:-${ROOT:?set ROOT or ROOT_DIR}}}/scripts/ci/waybar-test-sanitize-env.sh"

waybar_test_root() {
  printf '%s' "${WAYBAR_TEST_ROOT:-${ROOT_DIR:-${ROOT:?}}}"
}

waybar_test_begin() {
  local name="${1:-suite}"
  WAYBAR_TEST_SUITE_NAME="$name"
  fail=0
  waybar_test_sanitize_env
  SUITE_RUNTIME=$(mktemp -d)
  export XDG_RUNTIME_DIR="$SUITE_RUNTIME"
  # Default Hyprland-shaped configs without exporting HYPRLAND_INSTANCE_SIGNATURE.
  export WAYBAR_COMPOSITOR="${WAYBAR_COMPOSITOR:-hyprland}"
  trap 'rm -rf "${TEST_DIR:-}" "${SUITE_RUNTIME:-}" ${WAYBAR_TEST_EXTRA_CLEANUP:-}' EXIT
  echo "=== ${name} ==="
}

waybar_test_end() {
  if [ "${fail:-0}" -eq 0 ]; then
    echo "PASS: ${WAYBAR_TEST_SUITE_NAME:-suite}"
    exit 0
  fi
  echo "FAIL: ${WAYBAR_TEST_SUITE_NAME:-suite} had failures" >&2
  exit 1
}

waybar_test_fail() {
  echo "FAIL: $*" >&2
  fail=1
}

waybar_test_chmod_scripts() {
  local dir="${1:?dir}"
  find "$dir" \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} +
}
