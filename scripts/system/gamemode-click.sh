#!/usr/bin/env sh
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
action="${1:-toggle}"

# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

[ "$(detect_compositor)" = "hyprland" ] || exit 0
command -v hyprctl >/dev/null 2>&1 || exit 0

case "$action" in
  toggle)
    enabled="$(hyprctl getoption animations:enabled 2>/dev/null | awk '/int/ {print $2}')"
    if [ "$enabled" = "0" ]; then
      hyprctl reload >/dev/null 2>&1 || true
    else
      hyprctl --batch "
        keyword animations:enabled 0;
        keyword decoration:blur:enabled 0;
        keyword decoration:shadow:enabled 0
      " >/dev/null 2>&1 || true
    fi
    ;;
  restore)
    hyprctl reload >/dev/null 2>&1 || true
    ;;
  *)
    printf 'Usage: %s [toggle|restore]\n' "$0" >&2
    exit 1
    ;;
esac

"$WAYBAR_SCRIPTS/lib/waybar-signal.sh" gamemode
