#!/usr/bin/env bash
# CI test lib entrypoint — sources focused modules under scripts/ci/lib/.
#
# Suites should source only this file:
#   . "$ROOT/scripts/ci/lib/waybar-test-harness.sh"
#   waybar_test_begin "suite-name"
#   waybar_test_gen_sandbox   # or waybar_test_secrets_sandbox
#   ...
#   waybar_test_end
#
# Modules (edit these, not this file, for most changes):
#   waybar-test-core.sh      begin/end/fail/root
#   waybar-test-sandbox.sh   tree populate, generator + secrets sandboxes
#   waybar-test-assert.sh    JSONC/jq/mode/secrets write helpers
#   waybar-test-stubs.sh     PATH/script stubs + tracked mktemp
#   waybar-test-validate.sh  generated-config validators (generator suites)
#
# Assert helpers set fail=1 and return 0 so suites stay compatible with set -e.

_WAYBAR_TEST_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=waybar-test-core.sh
. "$_WAYBAR_TEST_LIB/waybar-test-core.sh"
# shellcheck source=waybar-test-sandbox.sh
. "$_WAYBAR_TEST_LIB/waybar-test-sandbox.sh"
# shellcheck source=waybar-test-assert.sh
. "$_WAYBAR_TEST_LIB/waybar-test-assert.sh"
# shellcheck source=waybar-test-stubs.sh
. "$_WAYBAR_TEST_LIB/waybar-test-stubs.sh"
# shellcheck source=waybar-test-validate.sh
. "$_WAYBAR_TEST_LIB/waybar-test-validate.sh"
unset _WAYBAR_TEST_LIB
