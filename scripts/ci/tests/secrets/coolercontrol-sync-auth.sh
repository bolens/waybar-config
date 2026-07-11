#!/usr/bin/env bash
# coolercontrol-set-ui-pass sudo-home + curl auth paths.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../lib/waybar-test-harness.sh
. "$ROOT/scripts/ci/lib/waybar-test-harness.sh"
waybar_test_begin "coolercontrol-sync-auth"
waybar_test_secrets_sandbox

CC_SYNC="$TEST_DIR/scripts/services/coolercontrol/coolercontrol-set-ui-pass.sh"
echo "Testing coolercontrol-set-ui-pass sudo-home and auth paths..."

# Simulated sudo home resolution (CC_TEST_SUDO_HOME)
SUDO_FAKE="$TEST_DIR/sudohome"
mkdir -p "$SUDO_FAKE/.config/waybar"/{data,scripts/{lib,services/coolercontrol}}
cp "$TEST_DIR/scripts/lib/waybar-settings.sh" "$SUDO_FAKE/.config/waybar/scripts/lib/"
cp "$CC_SYNC" "$SUDO_FAKE/.config/waybar/scripts/services/coolercontrol/"
cp "$TEST_DIR/data/waybar-settings.jsonc" "$SUDO_FAKE/.config/waybar/data/"
cp "$TEST_DIR/data/waybar-secrets.example.jsonc" "$SUDO_FAKE/.config/waybar/data/"
chmod +x "$SUDO_FAKE/.config/waybar/scripts/services/coolercontrol/"*.sh
out_sudo=$(
  CC_TEST_MODE=1 \
    HOME=/root \
    WAYBAR_HOME='' \
    SUDO_USER=fake-cc-user \
    CC_TEST_SUDO_HOME="$SUDO_FAKE" \
    WAYBAR_SCRIPTS=/root/.config/waybar/scripts \
    CC_UI_PASS_ENV="cc-sudo-pass-DDDD" \
    "$SUDO_FAKE/.config/waybar/scripts/services/coolercontrol/coolercontrol-set-ui-pass.sh" 2>&1
) || {
  echo "FAIL: sudo-home resolution bootstrap failed: $out_sudo" >&2
  fail=1
}
if [[ ! -f "$SUDO_FAKE/.config/waybar/data/waybar-secrets.jsonc" ]]; then
  echo "FAIL: sudo-home sync did not write secrets under CC_TEST_SUDO_HOME" >&2
  fail=1
fi
(
  WAYBAR_HOME="$SUDO_FAKE/.config/waybar"
  # shellcheck source=/dev/null
  . "$SUDO_FAKE/.config/waybar/scripts/lib/waybar-settings.sh"
  got=$(waybar_settings_get '.services.coolercontrol.ui_pass' '')
  if [[ "$got" != "cc-sudo-pass-DDDD" ]]; then
    echo "FAIL: sudo-home secrets mismatch (got: $got)" >&2
    exit 1
  fi
) || fail=1

# Mock curl auth path: must use POST /login (not GET) and Bearer /status
CC_CURL_FAKE="$TEST_DIR/fakebin"
mkdir -p "$CC_CURL_FAKE"
CC_CURL_LOG="$TEST_DIR/curl-args.log"
: >"$CC_CURL_LOG"
cat >"$CC_CURL_FAKE/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>$(printf '%q' "$CC_CURL_LOG")
joined="\$*"
if [[ "\$joined" == *"/status"* && "\$joined" == *"Authorization: Bearer"* ]]; then
  printf '200'
  exit 0
fi
if [[ "\$joined" == *"/login"* ]]; then
  if [[ "\$joined" != *"-X POST"* ]]; then
    printf '405'
    exit 0
  fi
  prev=""
  for a in "\$@"; do
    if [[ "\$prev" == "--netrc-file" && -f "\$a" ]]; then
      if grep -q 'invalid-auth-check' "\$a" 2>/dev/null; then
        printf '401'
        exit 0
      fi
    fi
    prev="\$a"
  done
  printf '200'
  exit 0
fi
printf '000'
exit 0
EOF
chmod +x "$CC_CURL_FAKE/curl"

# Ensure secrets have both creds for auth exercise
waybar_test_write_secrets <<'JSON'
{
  "services": {
    "coolercontrol": {
      "ui_user": "CCAdmin",
      "ui_pass": "cc-auth-pass-EEEE",
      "token": "cc_authtoken333333333333333333333"
    }
  }
}
JSON
out_auth=$(
  PATH="$CC_CURL_FAKE:/usr/bin:/bin" \
    CC_TEST_MODE=1 \
    CC_FORCE_AUTH_CHECK=1 \
    WAYBAR_HOME="$TEST_DIR" \
    "$CC_SYNC" 2>&1
) || {
  echo "FAIL: forced auth check failed: $out_auth" >&2
  fail=1
}
if ! grep -q 'API auth check: OK' <<<"$out_auth"; then
  echo "FAIL: expected successful mock API auth. Output: $out_auth" >&2
  echo "----- curl log -----" >&2
  cat "$CC_CURL_LOG" >&2 || true
  fail=1
fi
if ! grep -E -- '-X POST|.*/login' "$CC_CURL_LOG" >/dev/null 2>&1; then
  # Bearer success may short-circuit before login; ensure either Bearer /status or POST /login was used
  if ! grep -q '/status' "$CC_CURL_LOG"; then
    echo "FAIL: mock curl never saw /status or /login. Log:" >&2
    cat "$CC_CURL_LOG" >&2 || true
    fail=1
  fi
fi
# Bearer-only auth path
: >"$CC_CURL_LOG"
waybar_test_write_secrets <<'JSON'
{
  "services": {
    "coolercontrol": {
      "token": "cc_authtoken333333333333333333333"
    }
  }
}
JSON
out_auth_tok=$(
  PATH="$CC_CURL_FAKE:/usr/bin:/bin" \
    CC_TEST_MODE=1 \
    CC_FORCE_AUTH_CHECK=1 \
    WAYBAR_HOME="$TEST_DIR" \
    "$CC_SYNC" 2>&1
) || {
  echo "FAIL: bearer auth check failed: $out_auth_tok" >&2
  fail=1
}
if ! grep -q 'Bearer token' <<<"$out_auth_tok"; then
  echo "FAIL: expected Bearer token auth OK message. Output: $out_auth_tok" >&2
  fail=1
fi
if ! grep -q 'Authorization: Bearer' "$CC_CURL_LOG"; then
  echo "FAIL: mock curl missing Bearer header. Log:" >&2
  cat "$CC_CURL_LOG" >&2 || true
  fail=1
fi
# Basic-only auth path must POST /login
: >"$CC_CURL_LOG"
waybar_test_write_secrets <<'JSON'
{
  "services": {
    "coolercontrol": {
      "ui_user": "CCAdmin",
      "ui_pass": "cc-auth-pass-EEEE"
    }
  }
}
JSON
out_auth_basic=$(
  PATH="$CC_CURL_FAKE:/usr/bin:/bin" \
    CC_TEST_MODE=1 \
    CC_FORCE_AUTH_CHECK=1 \
    WAYBAR_HOME="$TEST_DIR" \
    "$CC_SYNC" 2>&1
) || {
  echo "FAIL: basic auth check failed: $out_auth_basic" >&2
  fail=1
}
if ! grep -q 'Basic login' <<<"$out_auth_basic"; then
  echo "FAIL: expected Basic login auth OK message. Output: $out_auth_basic" >&2
  fail=1
fi
if ! grep -E '(-X POST|/login)' "$CC_CURL_LOG" | grep -q '/login'; then
  echo "FAIL: basic auth must hit POST /login. Log:" >&2
  cat "$CC_CURL_LOG" >&2 || true
  fail=1
fi
if ! grep -q -- '-X POST' "$CC_CURL_LOG"; then
  echo "FAIL: /login must use POST (OpenAPI). Log:" >&2
  cat "$CC_CURL_LOG" >&2 || true
  fail=1
fi
# Password must not appear on curl argv (netrc only)
if grep -F 'cc-auth-pass-EEEE' "$CC_CURL_LOG"; then
  echo "FAIL: ui_pass appeared on curl argv" >&2
  fail=1
fi

# Bearer rejected → ui_pass fallback (sync helper)
: >"$CC_CURL_LOG"
cat >"$CC_CURL_FAKE/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>$(printf '%q' "$CC_CURL_LOG")
joined="\$*"
if [[ "\$joined" == *"/status"* && "\$joined" == *"Authorization: Bearer"* ]]; then
  if [[ "\$joined" == *"cc_bad"* ]]; then
    printf '401'
    exit 0
  fi
  printf '200'
  exit 0
fi
if [[ "\$joined" == *"/login"* ]]; then
  if [[ "\$joined" != *"-X POST"* ]]; then
    printf '405'
    exit 0
  fi
  prev=""
  for a in "\$@"; do
    if [[ "\$prev" == "--netrc-file" && -f "\$a" ]]; then
      if grep -q 'invalid-auth-check' "\$a" 2>/dev/null; then
        printf '401'
        exit 0
      fi
    fi
    prev="\$a"
  done
  printf '200'
  exit 0
fi
printf '000'
exit 0
EOF
chmod +x "$CC_CURL_FAKE/curl"
waybar_test_write_secrets <<'JSON'
{
  "services": {
    "coolercontrol": {
      "ui_user": "CCAdmin",
      "ui_pass": "cc-auth-pass-EEEE",
      "token": "cc_bad_token_should_fallback"
    }
  }
}
JSON
out_auth_fb=$(
  PATH="$CC_CURL_FAKE:/usr/bin:/bin" \
    CC_TEST_MODE=1 \
    CC_FORCE_AUTH_CHECK=1 \
    WAYBAR_HOME="$TEST_DIR" \
    "$CC_SYNC" 2>&1
) || {
  echo "FAIL: bearer→ui_pass fallback auth check failed: $out_auth_fb" >&2
  fail=1
}
if ! grep -qi 'ui_pass fallback\|trying ui_pass' <<<"$out_auth_fb"; then
  echo "FAIL: expected ui_pass fallback message. Output: $out_auth_fb" >&2
  fail=1
fi
if ! grep -q 'API auth check: OK' <<<"$out_auth_fb"; then
  echo "FAIL: fallback should still OK via ui_pass. Output: $out_auth_fb" >&2
  fail=1
fi
if ! grep -q 'Authorization: Bearer' "$CC_CURL_LOG"; then
  echo "FAIL: fallback should try Bearer first. Log:" >&2
  cat "$CC_CURL_LOG" >&2 || true
  fail=1
fi
if ! grep -q '/login' "$CC_CURL_LOG"; then
  echo "FAIL: fallback should POST /login. Log:" >&2
  cat "$CC_CURL_LOG" >&2 || true
  fail=1
fi

echo "PASS: coolercontrol-set-ui-pass auth"
waybar_test_end
