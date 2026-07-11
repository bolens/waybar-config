#!/usr/bin/env bash
# coolercontrol-set-ui-pass bootstrap / write / idempotency.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "coolercontrol-sync-bootstrap"
waybar_test_secrets_sandbox

# --- coolercontrol-set-ui-pass: comprehensive sync coverage ---
echo "Testing coolercontrol-set-ui-pass sync helper..."
CC_SYNC="$TEST_DIR/scripts/services/coolercontrol/coolercontrol-set-ui-pass.sh"
if ! bash -n "$CC_SYNC"; then
  echo "FAIL: coolercontrol-set-ui-pass.sh failed bash -n" >&2
  fail=1
fi
if ! grep -q 'coolercontrol' "$TEST_DIR/data/waybar-secrets.example.jsonc"; then
  echo "FAIL: waybar-secrets.example.jsonc missing coolercontrol block" >&2
  fail=1
fi

# Fail closed when secrets empty and no env bootstrap (non-TTY / test mode)
rm -f "$TEST_DIR/data/waybar-secrets.jsonc"
set +e
out_cc_fail=$(
  CC_TEST_MODE=1 \
    WAYBAR_HOME="$TEST_DIR" \
    "$CC_SYNC" 2>&1
)
rc_cc_fail=$?
set -e
if [[ "$rc_cc_fail" -eq 0 ]]; then
  echo "FAIL: coolercontrol sync should fail without credentials. Output: $out_cc_fail" >&2
  fail=1
fi

# CHANGE_ME in secrets counts as missing
waybar_test_write_secrets <<'JSON'
{
  "services": {
    "coolercontrol": {
      "ui_pass": "CHANGE_ME",
      "token": "CHANGE_ME"
    }
  }
}
JSON
set +e
out_cc_chg=$(
  CC_TEST_MODE=1 \
    WAYBAR_HOME="$TEST_DIR" \
    "$CC_SYNC" 2>&1
)
rc_cc_chg=$?
set -e
if [[ "$rc_cc_chg" -eq 0 ]]; then
  echo "FAIL: CHANGE_ME credentials should be treated as missing. Output: $out_cc_chg" >&2
  fail=1
fi

# Bootstrap pass+token from env; preserve sibling i2pd secret; mode 0600; no leak in output
waybar_test_write_secrets <<'JSON'
{
  "services": {
    "i2pd": {
      "console_pass": "overlay-secret-pass-AAAA"
    }
  }
}
JSON

# Stale /root scripts path must not win once WAYBAR_HOME is resolved
export WAYBAR_SCRIPTS=/root/.config/waybar/scripts
out_cc=$(
  CC_TEST_MODE=1 \
    WAYBAR_HOME="$TEST_DIR" \
    CC_UI_PASS_ENV="cc-test-ui-pass-BBBB" \
    CC_TOKEN_ENV="cc_testtoken0000000000000000000000" \
    "$CC_SYNC" 2>&1
) || {
  echo "FAIL: coolercontrol-set-ui-pass exited non-zero: $out_cc" >&2
  fail=1
}
unset WAYBAR_SCRIPTS
if grep -F 'cc-test-ui-pass-BBBB' <<<"$out_cc"; then
  echo "FAIL: sync output leaked ui_pass" >&2
  fail=1
fi
if grep -F 'cc_testtoken0000000000000000000000' <<<"$out_cc"; then
  echo "FAIL: sync output leaked token" >&2
  fail=1
fi
waybar_test_assert_mode "$TEST_DIR/data/waybar-secrets.jsonc" 600 "coolercontrol secrets mode"
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
  got_pass=$(waybar_settings_get '.services.coolercontrol.ui_pass' '')
  got_tok=$(waybar_settings_get '.services.coolercontrol.token' '')
  got_user=$(waybar_settings_get '.services.coolercontrol.ui_user' '')
  got_i2pd=$(waybar_settings_get '.services.i2pd.console_pass' '')
  if [[ "$got_pass" != "cc-test-ui-pass-BBBB" ]]; then
    echo "FAIL: coolercontrol ui_pass not written (got: $got_pass)" >&2
    exit 1
  fi
  if [[ "$got_tok" != "cc_testtoken0000000000000000000000" ]]; then
    echo "FAIL: coolercontrol token not written (got: $got_tok)" >&2
    exit 1
  fi
  if [[ "$got_user" != "CCAdmin" ]]; then
    echo "FAIL: coolercontrol ui_user default missing (got: $got_user)" >&2
    exit 1
  fi
  if [[ "$got_i2pd" != "overlay-secret-pass-AAAA" ]]; then
    echo "FAIL: coolercontrol sync clobbered i2pd console_pass" >&2
    exit 1
  fi
) || fail=1

# Idempotent re-run with credentials already present
out_cc2=$(
  CC_TEST_MODE=1 \
    WAYBAR_HOME="$TEST_DIR" \
    "$CC_SYNC" 2>&1
)
if ! grep -q 'credentials present\|unchanged\|Done' <<<"$out_cc2"; then
  echo "FAIL: coolercontrol re-run should be idempotent. Output: $out_cc2" >&2
  fail=1
fi
if grep -q 'wrote coolercontrol credentials' <<<"$out_cc2"; then
  echo "FAIL: idempotent re-run should not rewrite secrets. Output: $out_cc2" >&2
  fail=1
fi

# Token-only bootstrap
printf '{}\n' >"$TEST_DIR/data/waybar-secrets.jsonc"
out_tok=$(
  CC_TEST_MODE=1 \
    WAYBAR_HOME="$TEST_DIR" \
    CC_TOKEN_ENV="cc_onlytoken1111111111111111111111" \
    "$CC_SYNC" 2>&1
) || {
  echo "FAIL: token-only bootstrap failed: $out_tok" >&2
  fail=1
}
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
  got=$(waybar_settings_get '.services.coolercontrol.token' '')
  pass=$(waybar_settings_get '.services.coolercontrol.ui_pass' 'MISSING')
  if [[ "$got" != "cc_onlytoken1111111111111111111111" ]]; then
    echo "FAIL: token-only write mismatch (got: $got)" >&2
    exit 1
  fi
  if [[ "$pass" != "MISSING" && -n "$pass" && "$pass" != "null" && "$pass" != "CHANGE_ME" ]]; then
    echo "FAIL: token-only bootstrap should not invent ui_pass (got: $pass)" >&2
    exit 1
  fi
) || fail=1

# Pass-only bootstrap
printf '{}\n' >"$TEST_DIR/data/waybar-secrets.jsonc"
out_pass=$(
  CC_TEST_MODE=1 \
    WAYBAR_HOME="$TEST_DIR" \
    CC_UI_PASS_ENV="cc-pass-only-CCCC" \
    "$CC_SYNC" 2>&1
) || {
  echo "FAIL: pass-only bootstrap failed: $out_pass" >&2
  fail=1
}
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
  got=$(waybar_settings_get '.services.coolercontrol.ui_pass' '')
  tok=$(waybar_settings_get '.services.coolercontrol.token' 'MISSING')
  if [[ "$got" != "cc-pass-only-CCCC" ]]; then
    echo "FAIL: pass-only write mismatch (got: $got)" >&2
    exit 1
  fi
  if [[ "$tok" != "MISSING" && -n "$tok" && "$tok" != "null" && "$tok" != "CHANGE_ME" ]]; then
    echo "FAIL: pass-only bootstrap should not invent token (got: $tok)" >&2
    exit 1
  fi
) || fail=1

# Partial update: add token when pass already present
out_partial=$(
  CC_TEST_MODE=1 \
    WAYBAR_HOME="$TEST_DIR" \
    CC_TOKEN_ENV="cc_partialtoken2222222222222222222" \
    "$CC_SYNC" 2>&1
) || {
  echo "FAIL: partial token update failed: $out_partial" >&2
  fail=1
}
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
  got_pass=$(waybar_settings_get '.services.coolercontrol.ui_pass' '')
  got_tok=$(waybar_settings_get '.services.coolercontrol.token' '')
  if [[ "$got_pass" != "cc-pass-only-CCCC" ]]; then
    echo "FAIL: partial update clobbered ui_pass (got: $got_pass)" >&2
    exit 1
  fi
  if [[ "$got_tok" != "cc_partialtoken2222222222222222222" ]]; then
    echo "FAIL: partial update did not write token (got: $got_tok)" >&2
    exit 1
  fi
) || fail=1

echo "PASS: coolercontrol-set-ui-pass bootstrap"
waybar_test_end
