#!/usr/bin/env bash
# CoolerControl auth preference, fixture isolation, write-access cache.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT_DIR/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "coolercontrol-module-auth"
waybar_test_gen_sandbox

echo "Testing coolercontrol auth preference and fixture isolation..."
if ! waybar_test_gen_modules; then
  echo "FAIL: generate-settings.sh failed before coolercontrol auth checks" >&2
  fail=1
fi

# Auth preference: token over ui_pass; ui_pass fallback when token fails.
# Clear fixture/cache env so curl-mock auth is not shadowed by prior fixture tests
# or a polluted parent shell (WAYBAR_CC_FIXTURE_DIR pointing at a deleted mktemp).
unset WAYBAR_CC_FIXTURE_DIR || true
CC_AUTH_BIN="$TEST_DIR/cc-auth-bin"
mkdir -p "$CC_AUTH_BIN"
CC_AUTH_LOG="$TEST_DIR/cc-auth-curl.log"
: >"$CC_AUTH_LOG"
# Mock: bad token (cc_bad*) → 401 on Bearer /status; good token → 200; password login → 200 + cookie status
cat >"$CC_AUTH_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${CC_AUTH_LOG:?}"
joined="$*"
# Emit body\nhttp_code like real curl -w
emit() { printf '%s\n%s' "$1" "$2"; }
if [[ "$joined" == *"/status"* && "$joined" == *"Authorization: Bearer"* ]]; then
  if [[ "$joined" == *"cc_bad"* ]]; then
    emit '{"error":"unauthorized"}' "401"
  else
    emit '{"devices":[]}' "200"
  fi
  exit 0
fi
if [[ "$joined" == *"/login"* ]]; then
  if [[ "$joined" != *"-X POST"* ]]; then
    emit '' "405"
    exit 0
  fi
  emit '' "200"
  exit 0
fi
if [[ "$joined" == *"/status"* ]]; then
  # cookie session after login
  emit '{"devices":[]}' "200"
  exit 0
fi
if [[ "$joined" == *"/devices"* || "$joined" == *"/modes"* || "$joined" == *"/handshake"* ]]; then
  emit '{}' "200"
  exit 0
fi
if [[ "$joined" == *"/settings"* && "$joined" == *"PATCH"* ]]; then
  emit '{}' "403"
  exit 0
fi
emit '' "000"
exit 0
EOF
chmod +x "$CC_AUTH_BIN/curl"

# Both creds, good token → bearer only (no /login)
: >"$CC_AUTH_LOG"
auth_both=$(
  PATH="$CC_AUTH_BIN:/usr/bin:/bin" \
    CC_AUTH_LOG="$CC_AUTH_LOG" \
    WAYBAR_CC_FIXTURE_DIR='' \
    WAYBAR_CC_WRITE_PROBE_TTL=0 \
    WAYBAR_CC_API_URL="http://127.0.0.1:11987" \
    WAYBAR_CC_TOKEN="cc_good_token_aaaaaaaaaaaaaaaa" \
    WAYBAR_CC_UI_PASS="fallback-pass" \
    WAYBAR_CC_UI_USER="CCAdmin" \
    python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" fetch-bundle
) || true
waybar_test_assert_jq "$auth_both" '.ok == true and .auth == "bearer"' "both creds should prefer bearer auth: $auth_both"
if grep -q '/login' "$CC_AUTH_LOG"; then
  echo "FAIL: good token should not fall back to /login. Log:" >&2
  cat "$CC_AUTH_LOG" >&2 || true
  fail=1
fi

# Meta-guard: prove cmdline WAYBAR_CC_FIXTURE_DIR= clears a poisoned parent export.
# In bash, `export VAR=poison` then `VAR= cmd` → cmd sees empty VAR (assignment wins).
# Cases that forget the empty assign inherit poison and fail under set -e; keep this pattern.
echo "Verifying CoolerControl fixture isolation meta-guard..."
: >"$CC_AUTH_LOG"
poison_auth=$(
  export WAYBAR_CC_FIXTURE_DIR=/nonexistent-poison-cc-fixture
  PATH="$CC_AUTH_BIN:/usr/bin:/bin" \
    CC_AUTH_LOG="$CC_AUTH_LOG" \
    WAYBAR_CC_FIXTURE_DIR='' \
    WAYBAR_CC_WRITE_PROBE_TTL=0 \
    WAYBAR_CC_API_URL="http://127.0.0.1:11987" \
    WAYBAR_CC_TOKEN="cc_good_token_aaaaaaaaaaaaaaaa" \
    WAYBAR_CC_UI_PASS="fallback-pass" \
    WAYBAR_CC_UI_USER="CCAdmin" \
    python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" fetch-bundle
) || true
if ! echo "$poison_auth" | jq -e '.ok == true and .auth == "bearer"' >/dev/null 2>&1; then
  echo "FAIL: isolation meta-guard — poisoned WAYBAR_CC_FIXTURE_DIR must not break bearer auth: $poison_auth" >&2
  fail=1
else
  echo "PASS: CoolerControl fixture isolation meta-guard"
fi
unset WAYBAR_CC_FIXTURE_DIR || true

# Bad token + ui_pass → basic fallback
: >"$CC_AUTH_LOG"
auth_fb=$(
  PATH="$CC_AUTH_BIN:/usr/bin:/bin" \
    CC_AUTH_LOG="$CC_AUTH_LOG" \
    WAYBAR_CC_FIXTURE_DIR='' \
    WAYBAR_CC_WRITE_PROBE_TTL=0 \
    WAYBAR_CC_API_URL="http://127.0.0.1:11987" \
    WAYBAR_CC_TOKEN="cc_bad_token_bbbbbbbbbbbbbbbb" \
    WAYBAR_CC_UI_PASS="fallback-pass" \
    WAYBAR_CC_UI_USER="CCAdmin" \
    python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" fetch-bundle
) || true
waybar_test_assert_jq "$auth_fb" '.ok == true and .auth == "basic"' "bad token should fall back to ui_pass (basic): $auth_fb"
if ! grep -q 'Authorization: Bearer' "$CC_AUTH_LOG"; then
  echo "FAIL: fallback path should still try Bearer first. Log:" >&2
  cat "$CC_AUTH_LOG" >&2 || true
  fail=1
fi
if ! grep -q '/login' "$CC_AUTH_LOG"; then
  echo "FAIL: fallback path should POST /login. Log:" >&2
  cat "$CC_AUTH_LOG" >&2 || true
  fail=1
fi

# Bad token, no password → auth_failed
auth_fail=$(
  PATH="$CC_AUTH_BIN:/usr/bin:/bin" \
    CC_AUTH_LOG="$CC_AUTH_LOG" \
    WAYBAR_CC_FIXTURE_DIR='' \
    WAYBAR_CC_WRITE_PROBE_TTL=0 \
    WAYBAR_CC_API_URL="http://127.0.0.1:11987" \
    WAYBAR_CC_TOKEN="cc_bad_token_bbbbbbbbbbbbbbbb" \
    WAYBAR_CC_UI_PASS="" \
    python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" fetch-bundle
) || true
waybar_test_assert_jq "$auth_fail" '.ok == false and .error == "auth_failed"' "bad token without ui_pass should auth_failed: $auth_fail"

# Write-access probe cache: second fetch-bundle must not re-PATCH when TTL active
CC_WC_FIX=$(mktemp -d)
CC_WC_CACHE=$(mktemp -d)
echo 200 >"$CC_WC_FIX/write_http.txt"
echo '{"status":[{"status_history":[{"temp":42}]}]}' >"$CC_WC_FIX/status.json"
echo '{"devices":[{"name":"CPU"}]}' >"$CC_WC_FIX/devices.json"
echo '{"modes":[{"uid":"m1","name":"Quiet"}]}' >"$CC_WC_FIX/modes.json"
echo '{"current_mode_uid":"m1"}' >"$CC_WC_FIX/modes_active.json"
cc_w1=$(
  XDG_CACHE_HOME="$CC_WC_CACHE" \
    WAYBAR_CC_FIXTURE_DIR="$CC_WC_FIX" \
    WAYBAR_CC_WRITE_PROBE_TTL=600 \
    python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" fetch-bundle
) || true
waybar_test_assert_jq "$cc_w1" '.write_access == true' "write cache seed expected write_access true: $cc_w1"
echo 403 >"$CC_WC_FIX/write_http.txt"
cc_w2=$(
  XDG_CACHE_HOME="$CC_WC_CACHE" \
    WAYBAR_CC_FIXTURE_DIR="$CC_WC_FIX" \
    WAYBAR_CC_WRITE_PROBE_TTL=600 \
    python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" fetch-bundle
) || true
waybar_test_assert_jq "$cc_w2" '.write_access == true' "cached write_access should stay true after fixture flips to 403: $cc_w2"
cc_w3=$(
  XDG_CACHE_HOME="$CC_WC_CACHE" \
    WAYBAR_CC_FIXTURE_DIR="$CC_WC_FIX" \
    WAYBAR_CC_FORCE_WRITE_PROBE=1 \
    python3 "$TEST_DIR/scripts/services/coolercontrol/coolercontrol-api.py" fetch-bundle
) || true
waybar_test_assert_jq "$cc_w3" '.write_access == false' "FORCE_WRITE_PROBE should refresh to false (403): $cc_w3"
if [ ! -f "$CC_WC_CACHE/waybar/coolercontrol-write.json" ]; then
  echo "FAIL: coolercontrol write cache file missing" >&2
  fail=1
fi
rm -rf "$CC_WC_FIX" "$CC_WC_CACHE"

echo "PASS: coolercontrol module auth"
waybar_test_end
