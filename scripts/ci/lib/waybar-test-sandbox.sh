#!/usr/bin/env bash
# Sandbox + generate helpers (sourced via waybar-test-harness.sh).

# Populate dest with data/layouts/includes/modules/theme/scripts (no secrets).
# Optional second arg: "no-hyprland-stub" skips writing modules/hyprland.jsonc.
waybar_test_populate_tree() {
  local dest="${1:?dest}"
  local root
  root="$(waybar_test_root)"
  mkdir -p "$dest/data" "$dest/layouts" "$dest/includes" "$dest/modules" "$dest/theme"
  cp -r "$root/data/"* "$dest/data/"
  rm -f "$dest/data/waybar-secrets.jsonc" "$dest/data/waybar-secrets.json"
  cp "$root"/layouts/*.jsonc "$dest/layouts/" 2>/dev/null || true
  cp "$root"/includes/*.jsonc "$dest/includes/" 2>/dev/null || true
  cp "$root"/modules/*.jsonc "$dest/modules/" 2>/dev/null || true
  # Default stub prevents Hyprland generate failures in non-Hypr CI sandboxes.
  if [ "${2:-}" != "no-hyprland-stub" ]; then
    echo "{}" >"$dest/modules/hyprland.jsonc"
  fi
  cp -r "$root/scripts" "$dest/scripts"
  waybar_test_chmod_scripts "$dest/scripts"
}

waybar_test_gen_sandbox() {
  local root
  root="$(waybar_test_root)"
  TEST_DIR=$(mktemp -d)
  waybar_test_populate_tree "$TEST_DIR"
  export WAYBAR_HOME="$TEST_DIR"
  export WAYBAR_SCRIPTS="$TEST_DIR/scripts"
  ROOT_DIR="$root"
  ROOT="$root"
}

waybar_test_gen_default() {
  # On failure, dump generator stderr so suites do not only print "generate failed".
  local log
  log=$(mktemp "${TMPDIR:-/tmp}/waybar-gen.XXXXXX")
  if ! {
    "$TEST_DIR/scripts/generate/generate-settings.sh"
    "$TEST_DIR/scripts/generate/generate-compositor-modules.sh"
    "$TEST_DIR/scripts/generate/generate-workspaces-css.sh"
  } >"$log" 2>&1; then
    echo "FAIL: waybar_test_gen_default failed. Generator output:" >&2
    cat "$log" >&2 || true
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
  return 0
}

waybar_test_gen_modules() {
  local log
  log=$(mktemp "${TMPDIR:-/tmp}/waybar-gen.XXXXXX")
  if ! {
    "$TEST_DIR/scripts/generate/generate-settings.sh"
    "$TEST_DIR/scripts/generate/generate-compositor-modules.sh"
  } >"$log" 2>&1; then
    echo "FAIL: waybar_test_gen_modules failed. Generator output:" >&2
    cat "$log" >&2 || true
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
  return 0
}

waybar_test_gen_restore_sot() {
  local root
  root="$(waybar_test_root)"
  cp -f "$root/data/waybar-settings.jsonc" "$TEST_DIR/data/waybar-settings.jsonc"
  waybar_test_compile_settings
}

# Compile waybar-settings.jsonc → waybar-settings.json via lib helper.
# Suites that mutate settings mid-test often edit .json then `cp` → .jsonc so the
# next generate sees the patch. Production is jsonc → compile → json; that
# inversion is intentional for speed — do not "fix" it by only writing .jsonc
# without recompiling (or only writing .json without mirroring to .jsonc).
waybar_test_compile_settings() {
  local home="${1:-$TEST_DIR}"
  WAYBAR_HOME="$home" bash -c ". '$home/scripts/lib/waybar-settings.sh'" >/dev/null
}

# Minimal sandbox for secrets / settings exposure suites — sparse script copy
# (not a full tree) for isolation and speed.
waybar_test_secrets_sandbox() {
  local root fixture
  root="$(waybar_test_root)"
  fixture="$root/scripts/ci/lib/fixtures/settings/secrets-minimal-settings.jsonc"
  TEST_DIR=$(mktemp -d)
  mkdir -p "$TEST_DIR/data" \
    "$TEST_DIR/scripts"/{lib,services/{i2pd,coolercontrol,sync,apps,security,devices},ci,tools,workspaces,system,notifications} \
    "$TEST_DIR/i2pd" "$TEST_DIR/varlib"
  cp "$root/scripts/lib/waybar-settings.sh" "$root/scripts/lib/capture-lib.sh" \
    "$root/scripts/lib/settings-bool-lib.sh" "$root/scripts/lib/jsonc_util.py" \
    "$TEST_DIR/scripts/lib/"
  cp "$root/scripts/services/i2pd/i2pd-set-console-pass.sh" "$TEST_DIR/scripts/services/i2pd/"
  cp "$root/scripts/services/coolercontrol/coolercontrol-set-ui-pass.sh" "$TEST_DIR/scripts/services/coolercontrol/"
  cp "$root/scripts/ci/validate-generated-config.sh" "$TEST_DIR/scripts/ci/"
  cp "$root/data/waybar-secrets.example.jsonc" "$TEST_DIR/data/"
  cp "$fixture" "$TEST_DIR/data/waybar-settings.jsonc"
  waybar_test_chmod_scripts "$TEST_DIR/scripts"
  export WAYBAR_HOME="$TEST_DIR"
  export WAYBAR_SCRIPTS="$TEST_DIR/scripts"
  ROOT="$root"
  ROOT_DIR="$root"
}
