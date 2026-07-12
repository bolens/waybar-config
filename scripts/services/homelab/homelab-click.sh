#!/usr/bin/env bash
# Homelab clicks: menu|open-first|refresh
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

# shellcheck source=../../lib/waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck source=../../lib/rofi-popup-lib.sh
. "$WAYBAR_SCRIPTS/lib/rofi-popup-lib.sh"

action="${1:-menu}"
signal_num=$(waybar_settings_get '.signals.homelab' '33')
status_sh="$WAYBAR_SCRIPTS/services/homelab/homelab-status.sh"
app_open="$WAYBAR_SCRIPTS/tools/app-open.sh"

targets_json=$(waybar_settings_get '.homelab.targets' '[]')
count=$(printf '%s' "$targets_json" | jq 'if type=="array" then length else 0 end' 2>/dev/null || echo 0)

open_url() {
  local url="$1"
  [ -n "$url" ] || return 0
  if [ -x "$app_open" ]; then
    exec "$app_open" xdg-open "$url"
  fi
  exec xdg-open "$url"
}

first_url() {
  printf '%s' "$targets_json" | jq -r '.[0].url // empty' 2>/dev/null || true
}

signal_refresh() {
  "$status_sh" --refresh >/dev/null 2>&1 || true
  if [ -f "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" ]; then
    "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" "$signal_num" 2>/dev/null || true
  else
    pkill -x -RTMIN+"$signal_num" waybar >/dev/null 2>&1 || true
  fi
}

case "$action" in
  refresh)
    signal_refresh
    ;;
  open-first)
    url=$(first_url)
    [ -n "$url" ] || exit 0
    open_url "$url"
    ;;
  menu | '')
    if [ "$count" -eq 0 ]; then
      exit 0
    elif [ "$count" -eq 1 ]; then
      url=$(first_url)
      [ -n "$url" ] || exit 0
      open_url "$url"
    elif ! command -v rofi >/dev/null 2>&1; then
      url=$(first_url)
      [ -n "$url" ] || exit 0
      open_url "$url"
    else
      width=$(waybar_settings_get '.rofi.homelab.width' '420')
      lines=$(waybar_settings_get '.rofi.homelab.lines' '8')
      menu=$(
        printf '%s' "$targets_json" | jq -r '.[] | (.name // .url) + "\t" + (.url // "")' 2>/dev/null || true
      )
      [ -n "$menu" ] || exit 0
      theme_str="$(ROFI_THEME_WIDTH="$width" ROFI_THEME_LINES="$lines" rofi_theme_str_from_settings)"
      selected=$(printf '%s\n' "$menu" | rofi -dmenu -i -p "Homelab" \
        -theme-str "$theme_str" \
        -l "$lines" || true)
      [ -z "$selected" ] && exit 0
      url=$(printf '%s' "$selected" | awk -F'\t' '{print $NF}')
      [ -z "$url" ] && exit 0
      open_url "$url"
    fi
    ;;
  *)
    printf 'Usage: %s [menu|open-first|refresh]\n' "${0##*/}" >&2
    exit 64
    ;;
esac
