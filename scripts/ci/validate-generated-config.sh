#!/usr/bin/env bash
# Validate Waybar JSONC files parse as JSON (generated + key includes).
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

files=(
  "$WAYBAR_HOME"/modules/*.generated.jsonc
  "$WAYBAR_HOME"/includes/bar-defaults.generated.jsonc
  "$WAYBAR_HOME"/includes/modules.jsonc
  "$WAYBAR_HOME"/includes/stack.jsonc
  "$WAYBAR_HOME"/layouts/*.generated.jsonc
  "$WAYBAR_HOME"/layouts/top.jsonc
  "$WAYBAR_HOME"/layouts/bottom.jsonc
  "$WAYBAR_HOME"/config.jsonc
)

for file in "${files[@]}"; do
  [ -f "$file" ] || continue
  if strip_jsonc "$file" 2>/dev/null; then
    printf 'ok %s\n' "$file"
  else
    printf 'FAIL %s\n' "$file" >&2
    fail=1
  fi
done

# Contract checks
settings="$WAYBAR_HOME/data/waybar-settings.json"
if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
  if jq -e 'has("poll_intervals")' "$settings" >/dev/null 2>&1; then
    printf 'FAIL %s still has poll_intervals (use module_intervals only)\n' "$settings" >&2
    fail=1
  fi
  if jq -e '.services.i2pd.console_pass != null and (.services.i2pd.console_pass|type) == "string" and (.services.i2pd.console_pass|length) > 0' "$settings" >/dev/null 2>&1; then
    printf 'FAIL %s contains services.i2pd.console_pass — move to data/waybar-secrets.jsonc\n' "$settings" >&2
    fail=1
  fi
  if [ ! -f "$WAYBAR_HOME/modules/workspaces.generated.jsonc" ]; then
    printf 'FAIL missing modules/workspaces.generated.jsonc\n' >&2
    fail=1
  fi
  if ! jq -e '.bars.layer == "overlay" and .bars.tooltip == true' "$settings" >/dev/null 2>&1; then
    printf 'WARN %s: expected bars.layer=overlay and tooltip=true for KWin tooltips\n' "$settings" >&2
  fi
fi

exit "$fail"
