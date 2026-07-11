#!/usr/bin/env bash
# PATH / script stub helpers for hermetic runtime suites.
# Sourced via waybar-test-harness.sh.

waybar_test_lib_dir() {
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}

# mktemp -d tracked for suite EXIT cleanup (via WAYBAR_TEST_EXTRA_CLEANUP).
waybar_test_mktemp() {
  local d
  d=$(mktemp -d)
  WAYBAR_TEST_EXTRA_CLEANUP="${WAYBAR_TEST_EXTRA_CLEANUP:-} $d"
  printf '%s' "$d"
}

# Install default PATH stubs into $TEST_DIR/bin and prepend to PATH.
# Saves prior PATH in WAYBAR_TEST_HOST_PATH for compositor-gate / host-tool cases.
waybar_test_install_path_stubs() {
  local lib root
  lib="$(waybar_test_lib_dir)"
  root="$(waybar_test_root)"
  mkdir -p "$TEST_DIR/bin" "$TEST_DIR/cache"
  cp "$lib"/fixtures/bin-stubs/* "$TEST_DIR/bin/"
  chmod +x "$TEST_DIR"/bin/*
  : >"$TEST_DIR/bin/calls.log"
  export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$TEST_DIR/cache}"
  WAYBAR_TEST_HOST_PATH="${WAYBAR_TEST_HOST_PATH:-$PATH}"
  export PATH="$TEST_DIR/bin:$PATH"
}

# Copy named extras from fixtures/bin-stubs-extra/ into $TEST_DIR/bin.
waybar_test_install_path_stub_extras() {
  local lib name
  lib="$(waybar_test_lib_dir)"
  for name in "$@"; do
    cp "$lib/fixtures/bin-stubs-extra/$name" "$TEST_DIR/bin/$name"
    chmod +x "$TEST_DIR/bin/$name"
  done
}

# Write a one-off stub to $TEST_DIR/bin/$1 from stdin; chmod +x.
waybar_test_write_bin_stub() {
  local name="${1:?stub name}"
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/$name"
  chmod +x "$TEST_DIR/bin/$name"
}

# Install polish script stubs (app-open, compositor-gate, waybar-signal) into sandbox.
waybar_test_install_script_stubs() {
  local lib
  lib="$(waybar_test_lib_dir)"
  mkdir -p "$TEST_DIR/scripts/tools" "$TEST_DIR/scripts/lib"
  cp "$lib/fixtures/script-stubs/app-open.sh" "$TEST_DIR/scripts/tools/app-open.sh"
  cp "$lib/fixtures/script-stubs/compositor-gate.sh" "$TEST_DIR/scripts/lib/compositor-gate.sh"
  cp "$lib/fixtures/script-stubs/waybar-signal.sh" "$TEST_DIR/scripts/lib/waybar-signal.sh"
  chmod +x \
    "$TEST_DIR/scripts/tools/app-open.sh" \
    "$TEST_DIR/scripts/lib/compositor-gate.sh" \
    "$TEST_DIR/scripts/lib/waybar-signal.sh"
}

# Copy polish-runtime scripts into the secrets sandbox.
waybar_test_secrets_copy_polish_scripts() {
  local root
  root="$(waybar_test_root)"
  cp "$root/scripts/services/sync/updates-status.sh" "$TEST_DIR/scripts/services/sync/"
  cp "$root/scripts/services/apps/github-status.sh" "$TEST_DIR/scripts/services/apps/"
  cp "$root/scripts/services/security/privacy-click.sh" \
    "$root/scripts/services/security/vaults.py" \
    "$TEST_DIR/scripts/services/security/"
  cp "$root/scripts/services/sync/updates-review.sh" "$TEST_DIR/scripts/services/sync/"
  cp "$root/scripts/services/devices/kdeconnect-menu.sh" \
    "$root/scripts/services/devices/device-notifier.py" \
    "$TEST_DIR/scripts/services/devices/"
  cp "$root/scripts/lib/notifications-lib.sh" \
    "$root/scripts/lib/waybar-cache-helpers.sh" \
    "$root/scripts/lib/unicode-animations-lib.sh" \
    "$root/scripts/lib/compositor-session.sh" \
    "$TEST_DIR/scripts/lib/"
  cp "$root/scripts/workspaces/keybindhint-click.sh" "$TEST_DIR/scripts/workspaces/"
  cp "$root/scripts/system/powerprofiles-click.sh" "$TEST_DIR/scripts/system/"
  waybar_test_chmod_scripts "$TEST_DIR/scripts"
}
