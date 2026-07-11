#!/usr/bin/env bash
# Route clipboard status to the active compositor backend.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
# shellcheck source=clipboard-lib.sh
. "$WAYBAR_SCRIPTS/lib/clipboard-lib.sh"

compositor="$(detect_compositor)"

case "$compositor" in
  kde)
    exec "$script_dir/clipboard-status-kde.sh"
    ;;
  hyprland)
    exec "$script_dir/clipboard-status-cliphist.sh"
    ;;
  *)
    if cliphist_available; then
      exec "$script_dir/clipboard-status-cliphist.sh"
    fi
    if kde_klipper_available; then
      exec "$script_dir/clipboard-status-kde.sh"
    fi
    printf '{"text":"󰅌","class":"unknown","alt":"unknown","tooltip":"No clipboard manager found"}\n'
    ;;
esac
