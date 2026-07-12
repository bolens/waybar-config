#!/usr/bin/env bash
# Assert / IO helpers (sourced via waybar-test-harness.sh).
# All assert_* helpers set fail=1 on mismatch and return 0 (set -e safe).

# Strip JSONC comments and print JSON text (for piping into jq).
waybar_test_read_jsonc() {
  local file="$1"
  local lib="${WAYBAR_SCRIPTS:-${WAYBAR_HOME:-}/scripts}/lib"
  python3 - "$file" "$lib" <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[2])
from jsonc_util import strip_jsonc_comments

sys.stdout.write(strip_jsonc_comments(Path(sys.argv[1]).read_text(encoding="utf-8")))
PY
}

# Apply a jq program to settings JSONC, write pretty JSON back, compile .json.
# Comments in the JSONC are lost (same as other programmatic patchers).
# Usage: waybar_test_patch_settings 'JQ_FILTER' [HOME]
waybar_test_patch_settings() {
  local filter="${1:?jq filter}"
  local home="${2:-$TEST_DIR}"
  local jsonc="$home/data/waybar-settings.jsonc"
  python3 - "$jsonc" "$filter" "$home" <<'PY'
import json, sys
from pathlib import Path

jsonc = Path(sys.argv[1])
filt = sys.argv[2]
home = Path(sys.argv[3])
lib = home / "scripts" / "lib"
sys.path.insert(0, str(lib))
from jsonc_util import load_jsonc, strip_jsonc_comments
import subprocess

data = load_jsonc(jsonc)
raw = json.dumps(data)
proc = subprocess.run(
    ["jq", "-c", filt],
    input=raw,
    capture_output=True,
    text=True,
    check=False,
)
if proc.returncode != 0:
    sys.stderr.write(proc.stderr or "jq failed\n")
    sys.exit(1)
out = json.loads(proc.stdout)
jsonc.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
PY
  waybar_test_compile_settings "$home"
}

# Mutate settings JSONC via an inline Python body that receives `data` dict.
# Body is read from stdin. Writes pretty JSON (comments lost) and compiles.
# Usage: waybar_test_patch_settings_py <<'PY'
# data.setdefault("foo", {})["bar"] = True
# PY
waybar_test_patch_settings_py() {
  local home="${1:-$TEST_DIR}"
  local jsonc="$home/data/waybar-settings.jsonc"
  local body
  body=$(cat)
  python3 - "$jsonc" "$home" "$body" <<'PY'
import json, sys
from pathlib import Path

jsonc = Path(sys.argv[1])
home = Path(sys.argv[2])
body = sys.argv[3]
lib = home / "scripts" / "lib"
sys.path.insert(0, str(lib))
from jsonc_util import load_jsonc

data = load_jsonc(jsonc)
ns = {"data": data, "json": json}
exec(body, ns, ns)
data = ns["data"]
jsonc.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
  waybar_test_compile_settings "$home"
}

# Write secrets JSONC from stdin; mode 0600. Optional path (default: TEST_DIR secrets).
waybar_test_write_secrets() {
  local dest="${1:-$TEST_DIR/data/waybar-secrets.jsonc}"
  cat >"$dest"
  chmod 600 "$dest"
}

waybar_test_file_mode() {
  local path="${1:?path}"
  stat -c '%a' "$path" 2>/dev/null || stat -f '%OLp' "$path"
}

waybar_test_assert_mode() {
  local path="$1" expected="$2"
  local msg="${3:-$path mode}"
  local got
  got=$(waybar_test_file_mode "$path")
  if [[ "$got" != "$expected" && "$got" != "0$expected" ]]; then
    waybar_test_fail "$msg expected $expected (got $got)"
  fi
  return 0
}

waybar_test_assert_jq() {
  local json="$1" expr="$2" msg="$3"
  if ! printf '%s' "$json" | jq -e "$expr" >/dev/null 2>&1; then
    waybar_test_fail "$msg"
  fi
  return 0
}

waybar_test_assert_file_jq() {
  local file="$1" expr="$2" msg="$3"
  local json
  if ! json=$(waybar_test_read_jsonc "$file"); then
    waybar_test_fail "$msg (could not read $file)"
    return 0
  fi
  waybar_test_assert_jq "$json" "$expr" "$msg"
}

waybar_test_assert_json_file_jq() {
  local file="$1" expr="$2" msg="$3"
  if ! jq -e "$expr" "$file" >/dev/null 2>&1; then
    waybar_test_fail "$msg"
  fi
  return 0
}

waybar_test_assert_contains() {
  local hay="$1" needle="$2" msg="$3"
  if [[ "$hay" != *"$needle"* ]]; then
    waybar_test_fail "$msg (missing: $needle)"
  fi
  return 0
}

waybar_test_assert_not_contains() {
  local hay="$1" needle="$2" msg="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    waybar_test_fail "$msg (unexpected: $needle)"
  fi
  return 0
}

waybar_test_assert_file_exists() {
  local f="$1" msg="${2:-missing file: $1}"
  if [[ ! -f "$f" ]]; then
    waybar_test_fail "$msg"
  fi
  return 0
}

waybar_test_assert_bash_n() {
  local file="$1" msg="${2:-bash -n $1}"
  if ! bash -n "$file" 2>/dev/null; then
    waybar_test_fail "$msg"
  fi
  return 0
}
