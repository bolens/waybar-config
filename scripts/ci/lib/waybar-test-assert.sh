#!/usr/bin/env bash
# Assert / IO helpers (sourced via waybar-test-harness.sh).
# All assert_* helpers set fail=1 on mismatch and return 0 (set -e safe).

# Strip JSONC comments and print JSON text (for piping into jq).
waybar_test_read_jsonc() {
  python3 - "$1" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
text = re.sub(r'^\s*//.*$', '', text, flags=re.M)
sys.stdout.write(text)
PY
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
  local path="$1" expected="$2" msg="${3:-$path mode}"
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
