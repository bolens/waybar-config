#!/usr/bin/env bash
# i2pd-set-console-pass push/import/symlink repair.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "i2pd-sync"
waybar_test_secrets_sandbox

# Seed secrets for i2pd push (standalone; no longer depends on overlay suite).
waybar_test_write_secrets <<'JSON'
{
  "services": {
    "i2pd": {
      "console_pass": "overlay-secret-pass-AAAA"
    }
  }
}
JSON

# --- i2pd-set-console-pass: push secrets → conf ---
echo "Testing i2pd-set-console-pass push (secrets → conf)..."
cat >"$TEST_DIR/i2pd/i2pd.conf" <<'CONF'
[http]
address = 127.0.0.1
port = 7070
auth = false
# user = i2pd
# pass = old
[httpproxy]
password = unrelated-proxy-secret
CONF
ln -sfn "$TEST_DIR/i2pd/i2pd.conf" "$TEST_DIR/varlib/i2pd.conf"

# secrets already present from overlay test
out1=$(
  I2PD_TEST_MODE=1 \
    WAYBAR_HOME="$TEST_DIR" \
    I2PD_ETC_CONF="$TEST_DIR/i2pd/i2pd.conf" \
    I2PD_VAR_CONF="$TEST_DIR/varlib/i2pd.conf" \
    "$TEST_DIR/scripts/services/i2pd/i2pd-set-console-pass.sh" 2>&1
)
if ! grep -q 'updated:' <<<"$out1"; then
  echo "FAIL: expected conf update on first push. Output: $out1" >&2
  fail=1
fi
if ! grep -q 'auth = true' "$TEST_DIR/i2pd/i2pd.conf"; then
  echo "FAIL: auth not enabled in conf after push" >&2
  fail=1
fi
if ! awk '/^\[http\]/{h=1;next} /^\[/{h=0} h && /^pass[[:space:]]*=/{print; exit}' "$TEST_DIR/i2pd/i2pd.conf" \
  | grep -q 'overlay-secret-pass-AAAA'; then
  echo "FAIL: [http] pass not set from secrets" >&2
  fail=1
fi
# httpproxy password must remain untouched
if ! grep -q 'password = unrelated-proxy-secret' "$TEST_DIR/i2pd/i2pd.conf"; then
  echo "FAIL: [httpproxy] password was altered" >&2
  fail=1
fi

out2=$(
  I2PD_TEST_MODE=1 \
    WAYBAR_HOME="$TEST_DIR" \
    I2PD_ETC_CONF="$TEST_DIR/i2pd/i2pd.conf" \
    I2PD_VAR_CONF="$TEST_DIR/varlib/i2pd.conf" \
    "$TEST_DIR/scripts/services/i2pd/i2pd-set-console-pass.sh" 2>&1
)
if ! grep -q 'already up to date' <<<"$out2"; then
  echo "FAIL: second push should be idempotent. Output: $out2" >&2
  fail=1
fi
if grep -q 'updated:' <<<"$out2"; then
  echo "FAIL: second push should not rewrite conf. Output: $out2" >&2
  fail=1
fi
echo "PASS: i2pd push + idempotent re-run"

# --- i2pd-set-console-pass: import conf → secrets ---
echo "Testing i2pd-set-console-pass import (conf → secrets)..."
rm -f "$TEST_DIR/data/waybar-secrets.jsonc"
cat >"$TEST_DIR/i2pd/i2pd.conf" <<'CONF'
[http]
auth = true
user = i2pd
pass = imported-from-conf-BBBB
CONF
ln -sfn "$TEST_DIR/i2pd/i2pd.conf" "$TEST_DIR/varlib/i2pd.conf"

out3=$(
  I2PD_TEST_MODE=1 \
    WAYBAR_HOME="$TEST_DIR" \
    I2PD_ETC_CONF="$TEST_DIR/i2pd/i2pd.conf" \
    I2PD_VAR_CONF="$TEST_DIR/varlib/i2pd.conf" \
    "$TEST_DIR/scripts/services/i2pd/i2pd-set-console-pass.sh" 2>&1
)
if [[ ! -f "$TEST_DIR/data/waybar-secrets.jsonc" ]]; then
  echo "FAIL: secrets file not created on import. Output: $out3" >&2
  fail=1
fi
if ! grep -q 'imported console_pass\|unchanged (already matches)' <<<"$out3"; then
  echo "FAIL: expected import message. Output: $out3" >&2
  fail=1
fi
(
  # shellcheck source=/dev/null
  . "$TEST_DIR/scripts/lib/waybar-settings.sh"
  got=$(waybar_settings_get '.services.i2pd.console_pass' '')
  if [[ "$got" != "imported-from-conf-BBBB" ]]; then
    echo "FAIL: imported secrets pass mismatch" >&2
    exit 1
  fi
)

out4=$(
  I2PD_TEST_MODE=1 \
    WAYBAR_HOME="$TEST_DIR" \
    I2PD_ETC_CONF="$TEST_DIR/i2pd/i2pd.conf" \
    I2PD_VAR_CONF="$TEST_DIR/varlib/i2pd.conf" \
    "$TEST_DIR/scripts/services/i2pd/i2pd-set-console-pass.sh" 2>&1
)
if ! grep -q 'already up to date' <<<"$out4"; then
  echo "FAIL: import path should be idempotent on re-run. Output: $out4" >&2
  fail=1
fi
echo "PASS: i2pd import + idempotent re-run"

# --- symlink repair (divergent regular file) ---
echo "Testing i2pd var conf symlink repair..."
rm -f "$TEST_DIR/varlib/i2pd.conf"
echo 'not-a-real-conf' >"$TEST_DIR/varlib/i2pd.conf"
out5=$(
  I2PD_TEST_MODE=1 \
    WAYBAR_HOME="$TEST_DIR" \
    I2PD_ETC_CONF="$TEST_DIR/i2pd/i2pd.conf" \
    I2PD_VAR_CONF="$TEST_DIR/varlib/i2pd.conf" \
    "$TEST_DIR/scripts/services/i2pd/i2pd-set-console-pass.sh" 2>&1
)
if [[ ! -L "$TEST_DIR/varlib/i2pd.conf" ]]; then
  echo "FAIL: var conf should become symlink. Output: $out5" >&2
  fail=1
fi
if [[ ! -f "$TEST_DIR/varlib/i2pd.conf.bak" ]]; then
  echo "FAIL: divergent file should be backed up to .bak" >&2
  fail=1
fi
echo "PASS: symlink repair"
waybar_test_end
