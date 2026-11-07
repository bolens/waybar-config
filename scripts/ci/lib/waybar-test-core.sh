#!/usr/bin/env bash
# Lifecycle helpers for modular CI suites (sourced via waybar-test-harness.sh).

# shellcheck source=../waybar-test-sanitize-env.sh
. "${WAYBAR_TEST_ROOT:-${ROOT_DIR:-${ROOT:?set ROOT or ROOT_DIR}}}/scripts/ci/waybar-test-sanitize-env.sh"

waybar_test_root() {
  printf '%s' "${WAYBAR_TEST_ROOT:-${ROOT_DIR:-${ROOT:?}}}"
}

waybar_test_isolate_user_state() {
  local state="${1:?owned state directory}"
  # Generators must not read user configuration or warm the caller's icon cache.
  # Appicon-specific cases explicitly select their own controlled binary later.
  export HOME="$state/home"
  export XDG_CONFIG_HOME="$state/config"
  export XDG_CACHE_HOME="$state/cache"
  export XDG_DATA_HOME="$state/data"
  export XDG_STATE_HOME="$state/state"
  export TMPDIR="$state/tmp"
  export APPICON_BIN="$state/unavailable-appicon"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" \
    "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$TMPDIR"
}

waybar_test_begin() {
  local name="${1:-suite}"
  WAYBAR_TEST_SUITE_NAME="$name"
  fail=0
  waybar_test_sanitize_env
  # Cleanup targets belong to this suite, never to an inherited caller fixture.
  unset TEST_DIR WAYBAR_TEST_EXTRA_CLEANUP
  SUITE_RUNTIME=$(mktemp -d)
  trap 'rm -rf "${TEST_DIR:-}" "${SUITE_RUNTIME:-}" ${WAYBAR_TEST_EXTRA_CLEANUP:-}' EXIT
  export XDG_RUNTIME_DIR="$SUITE_RUNTIME"
  waybar_test_isolate_user_state "$SUITE_RUNTIME"
  # Default Hyprland-shaped configs without exporting HYPRLAND_INSTANCE_SIGNATURE.
  export WAYBAR_COMPOSITOR="${WAYBAR_COMPOSITOR:-hyprland}"
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
