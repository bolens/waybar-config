#!/usr/bin/env bash
# Validate generated Waybar JSONC files parse as JSON.
set -euo pipefail

WAYBAR_HOME="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
fail=0

strip_jsonc() {
  python3 - "$1" <<'PY'
import json, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
text = re.sub(r'^\s*//.*$', '', text, flags=re.M)
json.loads(text)
PY
}

for file in "$WAYBAR_HOME"/modules/*.generated.jsonc \
  "$WAYBAR_HOME"/includes/bar-defaults.generated.jsonc \
  "$WAYBAR_HOME"/layouts/*.generated.jsonc; do
  [ -f "$file" ] || continue
  if strip_jsonc "$file" 2>/dev/null; then
    printf 'ok %s\n' "$file"
  else
    printf 'FAIL %s\n' "$file" >&2
    fail=1
  fi
done

exit "$fail"
