#!/usr/bin/env sh
# Route notification status to the active compositor/daemon backend.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

compositor="$(detect_compositor)"

case "$compositor" in
  hyprland)
    if command -v swaync-client >/dev/null 2>&1; then
      exec swaync-client -swb
    fi
    if command -v makoctl >/dev/null 2>&1; then
      exec "$script_dir/notifications-status-mako.sh"
    fi
    printf '{"text":"󰂚","class":"unknown","tooltip":"Install swaync or mako on Hyprland"}\n'
    ;;
  kde)
    exec "$script_dir/notifications-status-kde.sh"
    ;;
  *)
    if command -v dunstctl >/dev/null 2>&1; then
      if dunstctl is-paused | rg -Fq true; then
        printf '{"text":"󰂛","class":"dnd-none","alt":"dnd-none","tooltip":"Notifications paused"}\n'
      else
        printf '{"text":"","class":"none","alt":"none","tooltip":"Notifications active"}\n'
      fi
      exit 0
    fi
    printf '{"text":"󰂚","class":"unknown","tooltip":"No supported notification daemon found"}\n'
    ;;
esac
