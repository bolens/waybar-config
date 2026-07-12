#!/usr/bin/env bash
# Generator resilience: missing settings + malformed JSON.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "generator-resilience"
waybar_test_gen_sandbox

echo "Verifying resilience against missing settings file..."
rm -f "$TEST_DIR/data/waybar-settings.jsonc" "$TEST_DIR/data/waybar-settings.json"
# Keep stderr so waybar_test_gen_modules can dump generator output on failure.
if ! waybar_test_gen_modules; then
  echo "FAIL: generate crashed when waybar-settings.jsonc was missing" >&2
  exit 1
fi

# Verify behavior when waybar-settings.jsonc contains invalid JSON syntax
echo "Verifying behavior with invalid JSON settings syntax..."
cat <<'JSON' >"$TEST_DIR/data/waybar-settings.jsonc"
{
  "bars": {
    "height": 99,
    "spacing": 99
  },
  "clocks": {
    "locale": "invalid_commas_here",,
  }
}
JSON

if "$TEST_DIR/scripts/generate/generate-settings.sh" >/dev/null 2>&1; then
  echo "FAIL: generate-settings.sh succeeded even with malformed waybar-settings.jsonc JSON!" >&2
  fail=1
else
  echo "PASS: generate-settings.sh correctly failed on malformed JSON settings."
fi
waybar_test_end
