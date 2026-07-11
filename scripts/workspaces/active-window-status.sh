#!/usr/bin/env bash
# Compositor-aware active window title for the center bar (KDE + Hyprland).
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

max_len=70
session="$(detect_compositor)"

escape_markup() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

desktop_json() {
  jq -cn '{text:"󰇄  Desktop",tooltip:"No active window",class:"desktop"}'
}

emit_json() {
  local title="$1"
  local tooltip="$2"
  local esc_title
  esc_title=$(escape_markup "$title")
  local esc_tooltip
  esc_tooltip=$(escape_markup "$tooltip")
  jq -cn --arg text "󰖲  $esc_title" --arg tooltip "$esc_tooltip" '{text:$text,tooltip:$tooltip,class:"active"}'
}

trim_title() {
  local s="$1"
  local max="${2:-$max_len}"
  s="${s//$'\n'/ }"
  s="${s//$'\t'/ }"
  s="$(printf '%s' "$s" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  s="$(printf '%s' "$s" | sed -E 's/(.*) - Mozilla Firefox/\1/; s/(.*) - Zen Browser/\1/; s/(.*) - Google Chrome/\1/; s/(.*) - Floorp/\1/; s/(.*) - Chromium/\1/; s/(.*) - Brave/\1/; s/(.*) - Vivaldi/\1/')"
  if [ "${#s}" -le "$max" ]; then
    printf '%s' "$s"
  else
    printf '%s...' "${s:0:$((max - 3))}"
  fi
}

case "$session" in
  hyprland)
    command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || { desktop_json; exit 0; }
    title="$(hyprctl activewindow -j 2>/dev/null | jq -r '.title // empty' || true)"
    if [ -n "$title" ]; then
      trimmed="$(trim_title "$title")"
      emit_json "$trimmed" "$title"
    else
      desktop_json
    fi
    ;;
  kde)
    cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/active-window.json"
    if [ -s "$cache_file" ]; then
      cat "$cache_file"
    else
      desktop_json
    fi
    ;;
  *)
    desktop_json
    ;;
esac
