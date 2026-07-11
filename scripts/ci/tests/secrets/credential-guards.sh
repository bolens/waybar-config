#!/usr/bin/env bash
# Validate credential guards, gitignore, secrets mode 600.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "credential-guards"
waybar_test_secrets_sandbox

# --- validate rejects console_pass in compiled settings ---
echo "Testing validate-generated-config console_pass guard..."
mkdir -p "$TEST_DIR/modules" "$TEST_DIR/includes" "$TEST_DIR/layouts"
# minimal generated stubs so validate doesn't fail for missing files
: >"$TEST_DIR/modules/workspaces.generated.jsonc"
echo '{}' >"$TEST_DIR/modules/workspaces.generated.jsonc"
# compile settings then inject forbidden pass into compiled JSON
waybar_test_compile_settings
jq '.services.i2pd.console_pass = "should-not-be-here"' \
  "$TEST_DIR/data/waybar-settings.json" >"$TEST_DIR/data/waybar-settings.json.tmp"
mv "$TEST_DIR/data/waybar-settings.json.tmp" "$TEST_DIR/data/waybar-settings.json"
if WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/ci/validate-generated-config.sh" >/dev/null 2>&1; then
  echo "FAIL: validate-generated-config should reject console_pass in settings JSON" >&2
  fail=1
else
  echo "PASS: validate rejects console_pass in settings"
fi
# restore clean compiled settings (no pass)
waybar_test_compile_settings

# --- validate rejects coolercontrol secrets in compiled settings ---
echo "Testing validate-generated-config coolercontrol credential guards..."
# Restore clean compiled settings before injecting leaks
waybar_test_compile_settings
jq '.services.coolercontrol.ui_pass = "should-not-be-here"' \
  "$TEST_DIR/data/waybar-settings.json" >"$TEST_DIR/data/waybar-settings.json.tmp"
mv "$TEST_DIR/data/waybar-settings.json.tmp" "$TEST_DIR/data/waybar-settings.json"
if WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/ci/validate-generated-config.sh" >/dev/null 2>&1; then
  echo "FAIL: validate should reject coolercontrol.ui_pass in settings JSON" >&2
  fail=1
else
  echo "PASS: validate rejects coolercontrol.ui_pass in settings"
fi
waybar_test_compile_settings
jq '.services.coolercontrol.token = "cc_should_not_be_here"' \
  "$TEST_DIR/data/waybar-settings.json" >"$TEST_DIR/data/waybar-settings.json.tmp"
mv "$TEST_DIR/data/waybar-settings.json.tmp" "$TEST_DIR/data/waybar-settings.json"
if WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/ci/validate-generated-config.sh" >/dev/null 2>&1; then
  echo "FAIL: validate should reject coolercontrol.token in settings JSON" >&2
  fail=1
else
  echo "PASS: validate rejects coolercontrol.token in settings"
fi
waybar_test_compile_settings

# --- gitignore: secrets ignored, example kept trackable ---
if ! git -C "$ROOT" check-ignore -q data/waybar-secrets.jsonc; then
  echo "FAIL: data/waybar-secrets.jsonc must be gitignored" >&2
  fail=1
fi
if ! git -C "$ROOT" check-ignore -q data/waybar-secrets.json; then
  echo "FAIL: data/waybar-secrets.json must be gitignored" >&2
  fail=1
fi
if git -C "$ROOT" check-ignore -q data/waybar-secrets.example.jsonc; then
  echo "FAIL: data/waybar-secrets.example.jsonc must NOT be gitignored" >&2
  fail=1
else
  echo "PASS: gitignore secrets vs example"
fi

# --- secrets file mode 600 (CI has no real secrets file; assert here) ---
waybar_test_write_secrets <<'JSON'
{ "services": { "i2pd": { "console_pass": "mode-check" } } }
JSON
chmod 644 "$TEST_DIR/data/waybar-secrets.jsonc"
mkdir -p "$TEST_DIR/modules" "$TEST_DIR/includes" "$TEST_DIR/layouts"
printf '{}\n' >"$TEST_DIR/modules/workspaces.generated.jsonc"
printf '{}\n' >"$TEST_DIR/data/waybar-settings.json"
if WAYBAR_HOME="$TEST_DIR" "$TEST_DIR/scripts/ci/validate-generated-config.sh" >/dev/null 2>&1; then
  echo "FAIL: validate should reject secrets mode 644" >&2
  fail=1
else
  echo "PASS: validate rejects secrets mode 644"
fi
chmod 600 "$TEST_DIR/data/waybar-secrets.jsonc"
_fail_before=$fail
waybar_test_assert_mode "$TEST_DIR/data/waybar-secrets.jsonc" 600 "secrets mode"
if [ "$fail" -eq "$_fail_before" ]; then
  echo "PASS: secrets mode 600 asserted"
fi
unset _fail_before
waybar_test_end
