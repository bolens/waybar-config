#!/usr/bin/env bash
# apply-profile.sh deep-merge + optional generate skip.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "apply-profile"
waybar_test_gen_sandbox

mkdir -p "$TEST_DIR/scripts/tools" "$TEST_DIR/scripts/lib" "$TEST_DIR/data/profiles"
cp "$ROOT_DIR/scripts/tools/apply-profile.sh" "$TEST_DIR/scripts/tools/"
cp "$ROOT_DIR/scripts/lib/waybar-settings.sh" "$TEST_DIR/scripts/lib/"
cp "$ROOT_DIR/data/profiles/minimal-groups.jsonc" "$TEST_DIR/data/profiles/"
chmod +x "$TEST_DIR/scripts/tools/apply-profile.sh"

# Baseline: full hardware group should mention coolercontrol in SoT (upstream default).
if ! grep -q 'coolercontrol' "$TEST_DIR/data/waybar-settings.jsonc"; then
  echo "FAIL: fixture settings expected to mention coolercontrol before profile" >&2
  fail=1
fi

echo "Testing apply-profile merges minimal-groups without generate..."
if ! WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_APPLY_PROFILE_GENERATE=0 \
  bash "$TEST_DIR/scripts/tools/apply-profile.sh" minimal-groups; then
  echo "FAIL: apply-profile.sh minimal-groups failed" >&2
  fail=1
fi

waybar_test_compile_settings
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" \
  '(.groups.hardware.modules | index("custom/coolercontrol")) == null' \
  "minimal-groups should drop custom/coolercontrol from hardware"
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" \
  '(.groups.hardware.modules | index("custom/cpu")) != null' \
  "minimal-groups should keep custom/cpu"
waybar_test_assert_json_file_jq "$TEST_DIR/data/waybar-settings.json" \
  '.homelab.targets == []' \
  "minimal-groups should clear homelab.targets"

echo "Testing missing profile fails..."
if WAYBAR_HOME="$TEST_DIR" WAYBAR_SCRIPTS="$TEST_DIR/scripts" \
  WAYBAR_APPLY_PROFILE_GENERATE=0 \
  bash "$TEST_DIR/scripts/tools/apply-profile.sh" does-not-exist >/dev/null 2>&1; then
  echo "FAIL: missing profile should exit non-zero" >&2
  fail=1
else
  echo "PASS: missing profile rejected"
fi

if ! bash -n "$TEST_DIR/scripts/tools/apply-profile.sh"; then
  echo "FAIL: apply-profile.sh bash -n" >&2
  fail=1
fi

waybar_test_end
