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
# Bearer may arrive as -H "Authorization: …" or -H @file (secrets off argv).
cat >"$CC_AUTH_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${CC_AUTH_LOG:?}"
joined="$*"
# Emit body\nhttp_code like real curl -w
emit() { printf '%s\n%s' "$1" "$2"; }

_bearer_hdr() {
  local prev="" a f
  for a in "$@"; do
    if [[ "$a" == *"Authorization: Bearer"* ]]; then
      printf '%s' "$a"
      return 0
    fi
    if [[ "$prev" == "-H" && "$a" == @* ]]; then
      f="${a#@}"
      if [[ -f "$f" ]]; then
        printf '%s' "$(tr -d '\n' <"$f")"
        return 0
      fi
    fi
    prev="$a"
  done
  return 1
}

if [[ "$joined" == *"/status"* ]]; then
  hdr="$(_bearer_hdr "$@" || true)"
  if [[ -n "$hdr" ]]; then
    if [[ "$hdr" == *"cc_bad"* ]]; then
      emit '{"error":"unauthorized"}' "401"
    else
      emit '{"devices":[]}' "200"
    fi
    exit 0
  fi
fi
if [[ "$joined" == *"/login"* ]]; then
  if [[ "$joined" != *"-X POST"* ]]; then
    emit '' "405"
    exit 0
  fi
  if [[ "$joined" != *"--netrc-file /dev/stdin"* || "$joined" == *"fallback-pass"* ]]; then
    emit '' "401"
    exit 0
  fi
  payload=$(cat)
  if [[ "$payload" != *"password fallback-pass"* ]]; then
    emit '' "401"
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
if grep -F 'cc_good_token_aaaaaaaaaaaaaaaa' "$CC_AUTH_LOG"; then
  echo "FAIL: bearer token must not appear on curl argv. Log:" >&2
  cat "$CC_AUTH_LOG" >&2 || true
  fail=1
fi
if ! grep -qE -- '-H @' "$CC_AUTH_LOG"; then
  echo "FAIL: bearer auth should use -H @file. Log:" >&2
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
if ! grep -qE -- '-H @' "$CC_AUTH_LOG"; then
  echo "FAIL: fallback path should try Bearer via -H @file first. Log:" >&2
  cat "$CC_AUTH_LOG" >&2 || true
  fail=1
fi
if grep -F 'cc_bad_token_bbbbbbbbbbbbbbbb' "$CC_AUTH_LOG"; then
  echo "FAIL: bearer token must not appear on curl argv. Log:" >&2
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

# Real curl must consume the password pipe and retain cookie authentication.
if ! python3 - "$ROOT_DIR" <<'PY'; then
import base64
import importlib.util
import os
from pathlib import Path
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch
import subprocess
import sys

spec = importlib.util.spec_from_file_location(
    "cc_api", Path(sys.argv[1]) / "scripts/services/coolercontrol/coolercontrol-api.py"
)
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)
password = "synthetic-stdin-password"
expected = "Basic " + base64.b64encode(f"CCAdmin:{password}".encode()).decode()

with tempfile.TemporaryDirectory() as root:
    class Handler(BaseHTTPRequestHandler):
        reject = False
        reject_status = False
        errors = []
        def log_message(self, *args):
            pass
        def do_POST(self):
            # Inspect files while credentials are in use, before cleanup can hide a leak.
            for path in Path(root).rglob("*"):
                if path.is_file():
                    if password.encode() in path.read_bytes():
                        self.errors.append(f"password file: {path.name}")
            ok = self.headers.get("Authorization") == expected and not self.reject
            self.send_response(200 if ok else 401)
            if ok:
                self.send_header("Set-Cookie", "session=synthetic; Path=/")
            self.end_headers()
        def do_GET(self):
            ok = self.headers.get("Cookie") == "session=synthetic" and not self.reject_status
            self.send_response(200 if ok else 401)
            self.end_headers()
            self.wfile.write(b'{"devices":[]}')

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    old_tempdir = tempfile.tempdir
    tempfile.tempdir = root
    try:
        with patch.dict(os.environ, {"WAYBAR_CC_UI_PASS": password, "WAYBAR_CC_UI_USER": "CCAdmin"}):
            client = api.CcClient()
        base = f"http://127.0.0.1:{server.server_port}"
        assert client._try_password(base), "real curl stdin login or cookie verification failed"
        client.close()
        assert not list(Path(root).iterdir()), "successful session cleanup failed"
        # Exercise the diagnostic and sync helpers' embedded Python with real curl.
        helper_dir = Path(sys.argv[1]) / "scripts/services/coolercontrol"
        child_env = dict(os.environ, CC_API_URL=base, CC_UI_USER="CCAdmin",
                         CC_UI_PASS=password, CC_TOKEN="", TMPDIR=root)
        for name, marker, args in (
            ("coolercontrol-api-dump.sh", "python3 <<'PY'", []),
            ("coolercontrol-set-ui-pass.sh", "python3 - \"$mode\" <<'PY' || true", ["basic_login"]),
        ):
            source = (helper_dir / name).read_text().split(marker + "\n", 1)[1].split("\nPY", 1)[0]
            result = subprocess.run([sys.executable, "-c", source, *args],
                                    env=child_env, capture_output=True, text=True, timeout=15)
            assert result.returncode == 0, (name, result.stderr)
            if args:
                assert result.stdout.strip() == "200", name
            else:
                import json
                assert json.loads(result.stdout)["auth"] == "basic+cookie", name
            assert not list(Path(root).iterdir()), (name, "session cleanup failed")
        Handler.reject_status = True
        assert not client._try_password(base), "rejected cookie verification accepted"
        assert not list(Path(root).iterdir()), "status rejection leaked session directory"
        Handler.reject_status = False
        Handler.reject = True
        assert not client._try_password(base), "rejected login accepted"
        assert not list(Path(root).iterdir()), "rejected login leaked session directory"
        with patch.object(api.subprocess, "run", side_effect=subprocess.TimeoutExpired("curl", 6)):
            assert not client._try_password(base), "timeout accepted"
        assert not list(Path(root).iterdir()), "timeout leaked session directory"
        assert not Handler.errors, Handler.errors
    finally:
        tempfile.tempdir = old_tempdir
        server.shutdown()
        server.server_close()
        worker.join()
PY
  echo "FAIL: real curl password transport or cleanup" >&2
  fail=1
fi

echo "PASS: coolercontrol module auth"
waybar_test_end
