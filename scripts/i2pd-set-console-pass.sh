#!/usr/bin/env bash
# Apply / sync i2pd web-console password between waybar-secrets and i2pd.conf.
#
# Direction (idempotent):
#   1) If data/waybar-secrets.jsonc has console_pass → push into /etc/i2pd/i2pd.conf
#   2) If secrets lack a pass but [http] pass exists in i2pd.conf → import into secrets
#   3) Re-run with the same state is a no-op (no rewrite, no restart, no bak spam)
#
# Also repairs /var/lib/i2pd/i2pd.conf into the tmpfiles symlink → /etc/i2pd/i2pd.conf.
# Never puts the password on argv; never prints it.
#
# Usage: sudo /path/to/i2pd-set-console-pass.sh
# Docs:  README.md → "Secrets (i2pd console)"
# Test:  I2PD_TEST_MODE=1 I2PD_ETC_CONF=... I2PD_VAR_CONF=... (skips root/systemd/auth)
set -euo pipefail

umask 077

I2PD_TEST_MODE="${I2PD_TEST_MODE:-0}"

if [[ "$(id -u)" -ne 0 && "$I2PD_TEST_MODE" != "1" ]]; then
  echo "Run as root (e.g. sudo $0)" >&2
  exit 1
fi

WAYBAR_HOME="${WAYBAR_HOME:-}"
if [[ -n "${SUDO_USER:-}" ]]; then
  SUDO_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  if [[ -z "$WAYBAR_HOME" || "$WAYBAR_HOME" == /root/.config/waybar ]]; then
    WAYBAR_HOME="$SUDO_HOME/.config/waybar"
  fi
fi
if [[ -z "$WAYBAR_HOME" ]]; then
  WAYBAR_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
fi

ETC_CONF="${I2PD_ETC_CONF:-/etc/i2pd/i2pd.conf}"
VAR_CONF="${I2PD_VAR_CONF:-/var/lib/i2pd/i2pd.conf}"
SECRETS_JSONC="${I2PD_SECRETS_JSONC:-$WAYBAR_HOME/data/waybar-secrets.jsonc}"
SECRETS_EXAMPLE="${I2PD_SECRETS_EXAMPLE:-$WAYBAR_HOME/data/waybar-secrets.example.jsonc}"
CHANGED=0

# shellcheck source=waybar-settings.sh
. "$WAYBAR_HOME/scripts/waybar-settings.sh"

I2PD_CONSOLE_USER="$(waybar_settings_get '.services.i2pd.console_user' 'i2pd')"
I2PD_CONSOLE_PASS="$(waybar_settings_get '.services.i2pd.console_pass' '')"
I2PD_CONSOLE_URL="$(waybar_settings_get '.services.i2pd.console_url' 'http://127.0.0.1:7070/')"

TMPDIR_AUTH=""
cleanup() {
  if [[ -n "${TMPDIR_AUTH}" && -d "${TMPDIR_AUTH}" ]]; then
    rm -rf "${TMPDIR_AUTH}"
  fi
  unset I2PD_CONSOLE_PASS I2PD_CONSOLE_USER I2PD_CONSOLE_URL
}
trap cleanup EXIT

secrets_pass_missing() {
  [[ -z "${I2PD_CONSOLE_PASS}" || "${I2PD_CONSOLE_PASS}" == "null" || "${I2PD_CONSOLE_PASS}" == "CHANGE_ME" ]]
}

# Import [http] pass from i2pd.conf into waybar-secrets.jsonc when secrets lack one.
# Idempotent: if secrets already contain the same pass, no rewrite.
# Does not set CHANGED (no i2pd restart needed for secrets-only bootstrap).
import_secrets_from_conf() {
  if [[ ! -f "$ETC_CONF" ]]; then
    echo "No console_pass in secrets and missing $ETC_CONF" >&2
    exit 1
  fi

  local owner="${SUDO_USER:-root}"
  local out rc
  set +e
  out=$(
    env -i PATH="/usr/bin:/bin" \
      I2PD_CONF_PATH="$ETC_CONF" \
      I2PD_SECRETS_PATH="$SECRETS_JSONC" \
      I2PD_SECRETS_EXAMPLE="$SECRETS_EXAMPLE" \
      python3 <<'PY'
import json, os, re, sys
from pathlib import Path

conf = Path(os.environ["I2PD_CONF_PATH"])
secrets_path = Path(os.environ["I2PD_SECRETS_PATH"])
example = Path(os.environ.get("I2PD_SECRETS_EXAMPLE", ""))

text = conf.read_text()
m = re.search(r"(?ms)^\[http\](.*?)(?=^\[|\Z)", text)
if not m:
    print("FAIL: no [http] section in i2pd.conf", file=sys.stderr)
    sys.exit(1)
pm = re.search(r"(?m)^pass\s*=\s*(.*)$", m.group(0))
um = re.search(r"(?m)^user\s*=\s*(.*)$", m.group(0))
password = (pm.group(1).strip() if pm else "")
user = (um.group(1).strip() if um else "i2pd")
if not password:
    print("FAIL: no [http] pass in i2pd.conf to import", file=sys.stderr)
    sys.exit(1)

def load_jsonc(path: Path):
    if not path.is_file():
        return {}
    raw = path.read_text()
    raw = re.sub(r"/\*.*?\*/", "", raw, flags=re.S)
    raw = re.sub(r"(?<!:)//.*", "", raw)
    raw = raw.strip()
    return json.loads(raw) if raw else {}

data = {}
if secrets_path.is_file():
    data = load_jsonc(secrets_path)
elif example.is_file():
    data = load_jsonc(example)

services = data.setdefault("services", {})
i2pd = services.setdefault("i2pd", {})
existing = i2pd.get("console_pass")
if existing == password:
    print("secrets: unchanged (already matches i2pd.conf)")
    sys.exit(0)

i2pd["console_pass"] = password
if user:
    i2pd.setdefault("console_user", user)

header = (
    "// Local secrets overlay — gitignored. Merged over waybar-settings at read time.\n"
    "// Managed/updated by scripts/i2pd-set-console-pass.sh — never commit.\n"
)
secrets_path.parent.mkdir(parents=True, exist_ok=True)
secrets_path.write_text(header + json.dumps(data, indent=2) + "\n")
secrets_path.chmod(0o600)
print(f"secrets: imported console_pass from {conf} -> {secrets_path}")
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
      I2PD_CONSOLE_PASS="$(waybar_settings_get '.services.i2pd.console_pass' '')"
      I2PD_CONSOLE_USER="$(waybar_settings_get '.services.i2pd.console_user' "$I2PD_CONSOLE_USER")"
      ;;
    *) exit "$rc" ;;
  esac
}

if secrets_pass_missing; then
  echo "secrets: console_pass missing; trying import from $ETC_CONF"
  import_secrets_from_conf
fi

if secrets_pass_missing; then
  echo "No console_pass in $SECRETS_JSONC (and none importable from i2pd.conf)." >&2
  echo "Copy data/waybar-secrets.example.jsonc -> data/waybar-secrets.jsonc and set console_pass." >&2
  exit 1
fi

if [[ ! -f "$ETC_CONF" ]]; then
  echo "Missing $ETC_CONF" >&2
  exit 1
fi

# Returns 0 if already correct symlink; 1 if repaired (sets CHANGED=1).
ensure_var_symlink() {
  mkdir -p "$(dirname "$VAR_CONF")"
  local etc_real
  etc_real=$(readlink -f "$ETC_CONF")

  if [[ -L "$VAR_CONF" ]]; then
    local target
    target=$(readlink -f "$VAR_CONF" 2>/dev/null || true)
    if [[ "$target" == "$etc_real" ]]; then
      echo "live conf: symlink OK ($VAR_CONF -> $ETC_CONF)"
      return 0
    fi
    echo "live conf: symlink points elsewhere; repairing -> $ETC_CONF" >&2
    rm -f "$VAR_CONF"
  elif [[ -f "$VAR_CONF" ]]; then
    # Regular file: only keep a single stable backup if content differs from /etc.
    if cmp -s "$VAR_CONF" "$ETC_CONF" 2>/dev/null; then
      echo "live conf: duplicate of /etc; replacing with symlink" >&2
      rm -f "$VAR_CONF"
    else
      local bak="${VAR_CONF}.bak"
      echo "live conf: divergent regular file; moving to $bak and linking -> $ETC_CONF" >&2
      rm -f "$bak"
      mv -f "$VAR_CONF" "$bak"
      chmod 600 "$bak" 2>/dev/null || true
    fi
  elif [[ -e "$VAR_CONF" ]]; then
    echo "live conf: unexpected type at $VAR_CONF" >&2
    exit 1
  fi

  ln -sfn "$ETC_CONF" "$VAR_CONF"
  CHANGED=1
  echo "live conf: symlink set $VAR_CONF -> $ETC_CONF"
}

# Exit 0 unchanged, 10 updated, 1 failure. Password via env only (not argv).
update_http_auth() {
  local conf="$1"
  [[ -e "$conf" ]] || return 0

  local real rc
  real=$(readlink -f "$conf")

  set +e
  env -i \
    PATH="/usr/bin:/bin" \
    I2PD_CONF_PATH="$real" \
    I2PD_CONSOLE_USER="$I2PD_CONSOLE_USER" \
    I2PD_CONSOLE_PASS="$I2PD_CONSOLE_PASS" \
    python3 <<'PY'
import os, re, sys
from pathlib import Path

path = Path(os.environ["I2PD_CONF_PATH"])
user = os.environ["I2PD_CONSOLE_USER"]
password = os.environ["I2PD_CONSOLE_PASS"]

text = path.read_text()
m = re.search(r"(?ms)^\[http\](.*?)(?=^\[|\Z)", text)
if not m:
    print(f"FAIL: no [http] section in {path}", file=sys.stderr)
    sys.exit(1)

section = m.group(0)
orig = section

def set_kv(section: str, key: str, value: str) -> str:
    pattern = rf"(?m)^(#\s*)?{re.escape(key)}\s*=\s*.*$"
    repl = f"{key} = {value}"
    if re.search(pattern, section):
        return re.sub(pattern, repl, section, count=1)
    return re.sub(r"(?m)^\[http\]\s*$", f"[http]\n{repl}", section, count=1)

section = set_kv(section, "auth", "true")
section = set_kv(section, "user", user)
section = set_kv(section, "pass", password)

pm = re.search(r"(?m)^pass\s*=\s*(.*)$", section)
if not pm or pm.group(1).strip() != password:
    print(f"FAIL: pass not applied in {path}", file=sys.stderr)
    sys.exit(1)

if section == orig:
    print(f"unchanged: {path}")
    sys.exit(0)

path.write_text(text[: m.start()] + section + text[m.end() :])
print(f"updated: {path}")
sys.exit(10)
PY
  rc=$?
  set -e

  case "$rc" in
    0) return 0 ;;
    10) CHANGED=1; return 0 ;;
    *) return "$rc" ;;
  esac
}

curl_http_code() {
  local login="$1"
  local password="$2"
  local url="$3"
  local netrc="$TMPDIR_AUTH/netrc"

  I2PD_NETRC_PATH="$netrc" \
  I2PD_CONSOLE_USER="$login" \
  I2PD_CONSOLE_PASS="$password" \
  python3 <<'PY'
import os
from pathlib import Path
path = Path(os.environ["I2PD_NETRC_PATH"])
user = os.environ["I2PD_CONSOLE_USER"]
password = os.environ["I2PD_CONSOLE_PASS"]
body = (
    f"machine 127.0.0.1\nlogin {user}\npassword {password}\n"
    f"machine localhost\nlogin {user}\npassword {password}\n"
)
path.write_text(body)
path.chmod(0o600)
PY

  curl -s -o /dev/null -w '%{http_code}' \
    --netrc-file "$netrc" \
    -H 'Host: localhost:7070' \
    "$url" || true

  rm -f "$netrc"
}

verify_console_auth() {
  if [[ "$I2PD_TEST_MODE" == "1" || "${I2PD_SKIP_AUTH_CHECK:-0}" == "1" ]]; then
    echo "console auth check: skipped (test mode)"
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "console auth check: skipped (curl not found)"
    return 0
  fi

  TMPDIR_AUTH=$(mktemp -d /tmp/i2pd-authcheck.XXXXXX)
  chmod 700 "$TMPDIR_AUTH"

  local code wrong
  code=$(curl_http_code "$I2PD_CONSOLE_USER" "$I2PD_CONSOLE_PASS" "$I2PD_CONSOLE_URL")
  wrong=$(curl_http_code "$I2PD_CONSOLE_USER" "invalid-auth-check" "$I2PD_CONSOLE_URL")

  rm -rf "$TMPDIR_AUTH"
  TMPDIR_AUTH=""

  if [[ "$code" == "200" && "$wrong" != "200" ]]; then
    echo "console auth check: OK (HTTP $code; reject-check HTTP $wrong)"
    return 0
  fi

  echo "console auth check: unexpected (ok=$code reject=$wrong)" >&2
  echo "Inspect [http] in $ETC_CONF (do not paste passwords into chat/logs)." >&2
  return 1
}

update_http_auth "$ETC_CONF"
ensure_var_symlink

ETC_REAL=$(readlink -f "$ETC_CONF")
VAR_REAL=$(readlink -f "$VAR_CONF")
if [[ -n "$VAR_REAL" && "$VAR_REAL" != "$ETC_REAL" ]]; then
  echo "WARN: live conf realpath differs from /etc; updating it as well" >&2
  update_http_auth "$VAR_REAL"
fi

if [[ "$I2PD_TEST_MODE" == "1" || "${I2PD_SKIP_SYSTEMD:-0}" == "1" ]]; then
  if [[ "$CHANGED" -eq 1 ]]; then
    echo "Done (changes applied; systemd skipped). Canonical: $ETC_CONF ; unit: $VAR_CONF -> ${VAR_REAL:-?}"
  else
    echo "Done (already up to date; systemd skipped). Canonical: $ETC_CONF ; unit: $VAR_CONF -> ${VAR_REAL:-?}"
  fi
elif [[ "$CHANGED" -eq 1 ]]; then
  systemctl restart i2pd.service
  systemctl --no-pager -l status i2pd.service | head -n 12
  sleep 1
  verify_console_auth
  echo "Done (changes applied). Canonical: $ETC_CONF ; unit: $VAR_CONF -> ${VAR_REAL:-?}"
else
  if systemctl is-active --quiet i2pd.service; then
    verify_console_auth
  else
    echo "i2pd inactive; starting to verify auth" >&2
    systemctl start i2pd.service
    sleep 1
    verify_console_auth
  fi
  echo "Done (already up to date; no restart). Canonical: $ETC_CONF ; unit: $VAR_CONF -> ${VAR_REAL:-?}"
fi

echo "Waybar reads the pass from data/waybar-secrets.jsonc (gitignored)."
