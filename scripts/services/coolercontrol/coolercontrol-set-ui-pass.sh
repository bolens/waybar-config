#!/usr/bin/env bash
# Bootstrap / verify CoolerControl UI credentials in waybar-secrets.
#
# Unlike i2pd, coolercontrold stores a password *hash* in /etc/coolercontrol/.passwd
# — there is no plaintext to import or push. This helper:
#   1) Ensures coolercontrold is enabled and running (keeps the daemon up)
#   2) If secrets already have ui_pass and/or token → verify API auth
#   3) If secrets lack credentials → interactive prompt (or env) → write secrets → verify
#
# Prefer a read-only Access Token (cc_…) for the status module; ui_pass is Basic Auth
# fallback (CCAdmin). Never prints credentials; never puts them on argv.
#
# Usage: sudo /path/to/coolercontrol-set-ui-pass.sh
# Docs:  README.md → "Secrets (CoolerControl)"
# Test:  CC_TEST_MODE=1 CC_SECRETS_JSONC=... CC_UI_PASS_ENV=... (skips root/systemd/auth)
#         CC_FORCE_AUTH_CHECK=1 + mock curl on PATH to exercise POST /login / Bearer checks
#         CC_TEST_SUDO_HOME=... to simulate sudo home resolution without getent
set -euo pipefail

umask 077

CC_TEST_MODE="${CC_TEST_MODE:-0}"

if [[ "$(id -u)" -ne 0 && "$CC_TEST_MODE" != "1" ]]; then
  echo "Run as root (e.g. sudo $0)" >&2
  exit 1
fi

# Resolve the invoking user's waybar tree under sudo (HOME is /root otherwise).
WAYBAR_HOME="${WAYBAR_HOME:-}"
if [[ "$CC_TEST_MODE" == "1" && -n "${CC_TEST_SUDO_HOME:-}" ]]; then
  # Test hook: simulate getent passwd "$SUDO_USER" without needing a real user.
  if [[ -z "$WAYBAR_HOME" || "$WAYBAR_HOME" == /root/.config/waybar ]]; then
    WAYBAR_HOME="$CC_TEST_SUDO_HOME/.config/waybar"
  fi
elif [[ -n "${SUDO_USER:-}" ]]; then
  SUDO_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  if [[ -z "$WAYBAR_HOME" || "$WAYBAR_HOME" == /root/.config/waybar ]]; then
    WAYBAR_HOME="$SUDO_HOME/.config/waybar"
  fi
fi
if [[ -z "$WAYBAR_HOME" ]]; then
  WAYBAR_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
fi
# Always derive scripts from the resolved home (do not keep a stale /root path).
WAYBAR_SCRIPTS="$WAYBAR_HOME/scripts"

SECRETS_JSONC="${CC_SECRETS_JSONC:-$WAYBAR_HOME/data/waybar-secrets.jsonc}"
SECRETS_EXAMPLE="${CC_SECRETS_EXAMPLE:-$WAYBAR_HOME/data/waybar-secrets.example.jsonc}"
SERVICE_NAME="${CC_SERVICE_NAME:-coolercontrold.service}"

# shellcheck source=waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

CC_UI_USER="$(waybar_settings_get '.services.coolercontrol.ui_user' 'CCAdmin')"
# Values currently stored in secrets/settings (before env override).
CC_UI_PASS="$(waybar_settings_get '.services.coolercontrol.ui_pass' '')"
CC_TOKEN="$(waybar_settings_get '.services.coolercontrol.token' '')"
CC_API_URL="$(waybar_settings_get '.services.coolercontrol.api_url' 'http://127.0.0.1:11987')"
CC_API_URL="${CC_API_URL%/}"

SECRETS_PASS_MISSING=0
SECRETS_TOKEN_MISSING=0
if [[ -z "$CC_UI_PASS" || "$CC_UI_PASS" == "null" || "$CC_UI_PASS" == "CHANGE_ME" ]]; then
  SECRETS_PASS_MISSING=1
fi
if [[ -z "$CC_TOKEN" || "$CC_TOKEN" == "null" || "$CC_TOKEN" == "CHANGE_ME" ]]; then
  SECRETS_TOKEN_MISSING=1
fi

# Non-interactive bootstrap (tests / automation): only used when secrets lack credentials.
if [[ "$SECRETS_PASS_MISSING" -eq 1 && -n "${CC_UI_PASS_ENV:-}" ]]; then
  CC_UI_PASS="$CC_UI_PASS_ENV"
fi
if [[ "$SECRETS_TOKEN_MISSING" -eq 1 && -n "${CC_TOKEN_ENV:-}" ]]; then
  CC_TOKEN="$CC_TOKEN_ENV"
fi

TMPDIR_AUTH=""
cleanup() {
  if [[ -n "${TMPDIR_AUTH}" && -d "${TMPDIR_AUTH}" ]]; then
    rm -rf "${TMPDIR_AUTH}"
  fi
  unset CC_UI_PASS CC_TOKEN CC_UI_USER CC_API_URL
}
trap cleanup EXIT

cred_missing() {
  local pass="$1" token="$2"
  local pass_bad=0 token_bad=0
  if [[ -z "$pass" || "$pass" == "null" || "$pass" == "CHANGE_ME" ]]; then
    pass_bad=1
  fi
  if [[ -z "$token" || "$token" == "null" || "$token" == "CHANGE_ME" ]]; then
    token_bad=1
  fi
  [[ "$pass_bad" -eq 1 && "$token_bad" -eq 1 ]]
}

write_secrets() {
  local pass="$1" token="$2" user="$3"
  local owner="${SUDO_USER:-root}"
  local out rc

  set +e
  out=$(
    env -i PATH="/usr/bin:/bin" \
      CC_SECRETS_PATH="$SECRETS_JSONC" \
      CC_SECRETS_EXAMPLE="$SECRETS_EXAMPLE" \
      CC_UI_USER="$user" \
      CC_UI_PASS="$pass" \
      CC_TOKEN="$token" \
      WAYBAR_SCRIPTS="$WAYBAR_SCRIPTS" \
      python3 <<'PY'
import json, os, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(os.environ["WAYBAR_SCRIPTS"]) / "lib"))
from jsonc_util import load_jsonc

secrets_path = Path(os.environ["CC_SECRETS_PATH"])
example = Path(os.environ.get("CC_SECRETS_EXAMPLE", ""))
user = os.environ.get("CC_UI_USER", "CCAdmin").strip() or "CCAdmin"
password = os.environ.get("CC_UI_PASS", "").strip()
token = os.environ.get("CC_TOKEN", "").strip()

data = {}
if secrets_path.is_file():
    data = load_jsonc(secrets_path)
elif example.is_file():
    data = load_jsonc(example)

services = data.setdefault("services", {})
cc = services.setdefault("coolercontrol", {})
# Drop placeholder values copied from the example template.
for key in ("ui_pass", "token"):
    if cc.get(key) in ("CHANGE_ME", "", None):
        cc.pop(key, None)
# Never pull sibling service placeholders into a coolercontrol-only write.
i2pd = (services.get("i2pd") or {})
if isinstance(i2pd, dict) and i2pd.get("console_pass") in ("CHANGE_ME", "", None):
    i2pd.pop("console_pass", None)
    if not i2pd:
        services.pop("i2pd", None)

changed = False

if password and password not in ("CHANGE_ME", "null"):
    if cc.get("ui_pass") != password:
        cc["ui_pass"] = password
        changed = True
    if user and cc.get("ui_user") != user:
        cc["ui_user"] = user
        changed = True
if token and token not in ("CHANGE_ME", "null"):
    if cc.get("token") != token:
        cc["token"] = token
        changed = True

# If we only scrubbed placeholders, treat as needing a real write when new values exist.
if not changed and (cc.get("ui_pass") or cc.get("token")):
    print("secrets: unchanged")
    sys.exit(0)

if not (cc.get("ui_pass") or cc.get("token")):
    print("FAIL: nothing to write (need ui_pass and/or token)", file=sys.stderr)
    sys.exit(1)

header = (
    "// Local secrets overlay — gitignored. Merged over waybar-settings at read time.\n"
    "// Managed/updated by scripts/services/coolercontrol/coolercontrol-set-ui-pass.sh — never commit.\n"
)
secrets_path.parent.mkdir(parents=True, exist_ok=True)
secrets_path.write_text(header + json.dumps(data, indent=2) + "\n")
secrets_path.chmod(0o600)
print(f"secrets: wrote coolercontrol credentials -> {secrets_path}")
sys.exit(10)
PY
  )
  rc=$?
  set -e
  printf '%s\n' "$out"
  case "$rc" in
    0) ;;
    10)
      if [[ -n "${SUDO_USER:-}" ]]; then
        chown "$owner":"$owner" "$SECRETS_JSONC" 2>/dev/null || true
      fi
      # Reload from merged settings
      CC_UI_PASS="$(waybar_settings_get '.services.coolercontrol.ui_pass' '')"
      CC_TOKEN="$(waybar_settings_get '.services.coolercontrol.token' '')"
      CC_UI_USER="$(waybar_settings_get '.services.coolercontrol.ui_user' "$CC_UI_USER")"
      ;;
    *) exit "$rc" ;;
  esac
}

prompt_credentials() {
  if [[ "$CC_TEST_MODE" == "1" ]]; then
    if [[ -n "${CC_UI_PASS_ENV:-}" || -n "${CC_TOKEN_ENV:-}" ]]; then
      CC_UI_PASS="${CC_UI_PASS_ENV:-}"
      CC_TOKEN="${CC_TOKEN_ENV:-}"
      return 0
    fi
    echo "No coolercontrol credentials in secrets (and CC_UI_PASS_ENV/CC_TOKEN_ENV unset in test mode)." >&2
    exit 1
  fi

  if [[ ! -t 0 ]]; then
    echo "No coolercontrol credentials in $SECRETS_JSONC." >&2
    echo "Copy data/waybar-secrets.example.jsonc → data/waybar-secrets.jsonc and set" >&2
    echo "  services.coolercontrol.ui_pass  and/or  services.coolercontrol.token" >&2
    echo "Or re-run this script from a TTY to be prompted." >&2
    exit 1
  fi

  echo "CoolerControl stores a password hash — enter the UI password you set in Access Protection."
  echo "(Optional: leave password blank if you only have a Bearer token.)"
  local pass="" token=""
  read -r -s -p "UI password (CCAdmin): " pass
  echo
  read -r -s -p "Bearer token (cc_…, optional, preferred for Waybar): " token
  echo

  if [[ -z "$pass" && -z "$token" ]]; then
    echo "Need at least a UI password or a Bearer token." >&2
    exit 1
  fi
  CC_UI_PASS="$pass"
  CC_TOKEN="$token"
}

ensure_service() {
  if [[ "$CC_TEST_MODE" == "1" || "${CC_SKIP_SYSTEMD:-0}" == "1" ]]; then
    echo "service: skipped (test mode)"
    return 0
  fi
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "service: systemctl not found; skip enable" >&2
    return 0
  fi

  systemctl enable --now "$SERVICE_NAME"
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "service: $SERVICE_NAME active (enabled)"
  else
    echo "service: failed to start $SERVICE_NAME" >&2
    systemctl --no-pager -l status "$SERVICE_NAME" | head -n 16 || true
    exit 1
  fi
}

curl_code() {
  # Credentials via env only. Basic auth uses a temp netrc (not curl -u argv).
  local mode="$1" # token | basic_login | wrong_login
  python3 - "$mode" <<'PY' || true
import os, subprocess, sys, tempfile
from pathlib import Path

mode = sys.argv[1]
api = os.environ["CC_API_URL"].rstrip("/")
user = os.environ.get("CC_UI_USER", "CCAdmin")
password = os.environ.get("CC_UI_PASS", "")
token = os.environ.get("CC_TOKEN", "")

def run(args):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=5)
        return (r.stdout or "").strip() or "000"
    except Exception:
        return "000"

# Prefer HTTP on localhost (daemon always allows plain HTTP on loopback).
base_http = api.replace("https://", "http://") if api.startswith("https://") else api
base_https = api if api.startswith("https://") else api.replace("http://", "https://")

def with_netrc(login, passwd, build_args):
    with tempfile.TemporaryDirectory(prefix="cc-netrc.") as td:
        netrc = Path(td) / "netrc"
        netrc.write_text(
            f"machine 127.0.0.1\nlogin {login}\npassword {passwd}\n"
            f"machine localhost\nlogin {login}\npassword {passwd}\n"
        )
        netrc.chmod(0o600)
        for base in (base_http, base_https):
            args = build_args(base, str(netrc))
            if base.startswith("https://"):
                args = args[:1] + ["-k"] + args[1:]
            code = run(args)
            if code and code != "000":
                return code
    return "000"

def try_bases(build_args):
    for base in (base_http, base_https):
        args = build_args(base)
        if base.startswith("https://"):
            args = args[:1] + ["-k"] + args[1:]
        code = run(args)
        if code and code != "000":
            return code
    return "000"

if mode == "token":
    # Bearer via -H @file so the token never appears on curl argv.
    with tempfile.TemporaryDirectory(prefix="cc-tok.") as td:
        hdr = Path(td) / "bearer.hdr"
        hdr.write_text(f"Authorization: Bearer {token}\n", encoding="utf-8")
        hdr.chmod(0o600)

        def build(base, hdr_path=str(hdr)):
            return [
                "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                "--max-time", "3",
                "-H", f"@{hdr_path}",
                f"{base}/status",
            ]

        print(try_bases(build))
elif mode == "basic_login":
    def build(base, netrc):
        return [
            "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
            "--max-time", "3", "-X", "POST",
            "--netrc-file", netrc,
            f"{base}/login",
        ]
    print(with_netrc(user, password, build))
elif mode == "wrong_login":
    def build(base, netrc):
        return [
            "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
            "--max-time", "3", "-X", "POST",
            "--netrc-file", netrc,
            f"{base}/login",
        ]
    print(with_netrc(user, "invalid-auth-check", build))
else:
    print("000")
PY
}

verify_api_auth() {
  # CC_FORCE_AUTH_CHECK=1 runs the real curl path even in CC_TEST_MODE (for unit tests with a mock curl).
  if [[ "${CC_FORCE_AUTH_CHECK:-0}" != "1" ]] && [[ "$CC_TEST_MODE" == "1" || "${CC_SKIP_AUTH_CHECK:-0}" == "1" ]]; then
    echo "API auth check: skipped (test mode)"
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "API auth check: skipped (curl not found)"
    return 0
  fi

  export CC_API_URL CC_UI_USER CC_UI_PASS CC_TOKEN

  local code wrong
  if [[ -n "$CC_TOKEN" && "$CC_TOKEN" != "CHANGE_ME" && "$CC_TOKEN" != "null" ]]; then
    code=$(curl_code token)
    if [[ "$code" == "200" ]]; then
      echo "API auth check: OK (Bearer token → /status HTTP $code)"
      return 0
    fi
    echo "API auth check: Bearer token rejected (HTTP $code); trying ui_pass fallback…" >&2
  fi

  if [[ -n "$CC_UI_PASS" && "$CC_UI_PASS" != "CHANGE_ME" && "$CC_UI_PASS" != "null" ]]; then
    code=$(curl_code basic_login)
    wrong=$(curl_code wrong_login)
    if [[ "$code" == "200" && "$wrong" != "200" ]]; then
      if [[ -n "$CC_TOKEN" && "$CC_TOKEN" != "CHANGE_ME" && "$CC_TOKEN" != "null" ]]; then
        echo "API auth check: OK (ui_pass fallback → HTTP $code; reject-check HTTP $wrong)"
      else
        echo "API auth check: OK (Basic login → HTTP $code; reject-check HTTP $wrong)"
      fi
      return 0
    fi
    echo "API auth check: unexpected (ok=$code reject=$wrong)" >&2
    echo "Confirm the UI password in CoolerControl Access Protection (do not paste it into chat/logs)." >&2
    echo "Tip: create a read-only Access Token (cc_…) and set services.coolercontrol.token in secrets." >&2
    return 1
  fi

  echo "API auth check: no usable credentials" >&2
  return 1
}

# --- main ---
ensure_service

if cred_missing "$CC_UI_PASS" "$CC_TOKEN"; then
  # Still empty after optional env fill → interactive prompt (or fail in test/non-TTY).
  echo "secrets: coolercontrol credentials missing; prompting"
  prompt_credentials
  write_secrets "$CC_UI_PASS" "$CC_TOKEN" "$CC_UI_USER"
elif [[ "$SECRETS_PASS_MISSING" -eq 1 || "$SECRETS_TOKEN_MISSING" -eq 1 ]]; then
  # Env (or partial secrets) supplied credentials that are not yet persisted.
  echo "secrets: writing coolercontrol credentials from bootstrap input"
  write_secrets "$CC_UI_PASS" "$CC_TOKEN" "$CC_UI_USER"
else
  echo "secrets: coolercontrol credentials present"
fi

verify_api_auth

echo "Done. Waybar reads credentials from data/waybar-secrets.jsonc (gitignored)."
echo "Prefer a read-only Access Token (Access Protection → Create Token) as services.coolercontrol.token."
