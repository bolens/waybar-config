#!/usr/bin/env bash
# One dock-windows slot: glyph + active/inactive/hidden (workspace-switcher pattern).
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

slot="${1:-}"
output_arg="${2:-}"
if [ -n "$output_arg" ]; then
  export WAYBAR_OUTPUT_NAME="$output_arg"
fi

if [ -z "$slot" ] || ! [[ "$slot" =~ ^[0-9]+$ ]]; then
  printf '{"text":"","tooltip":"","class":["hidden"]}\n'
  exit 0
fi

list="$("$WAYBAR_SCRIPTS/dock/dock-windows-query.sh" "${WAYBAR_OUTPUT_NAME:-}" 2>/dev/null || echo '[]')"
row=$(printf '%s' "$list" | jq -c --argjson i "$slot" '.[$i] // empty' 2>/dev/null || true)

if [ -z "$row" ] || [ "$row" = "null" ]; then
  printf '{"text":"","tooltip":"","class":["hidden"]}\n'
  exit 0
fi

printf '%s' "$row" | jq -c '
  {
    text: (.icon // ""),
    tooltip: (.title // .app // "Window"),
    class: (
      ["dock-win-hit"]
      + (if .focused then ["dock-win-active"] else ["dock-win-inactive"] end)
    )
  }
'
