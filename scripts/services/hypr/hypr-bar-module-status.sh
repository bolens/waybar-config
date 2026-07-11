#!/usr/bin/env sh
# Hide Hyprland-only bar modules when not running Hyprland (hyprwhspr stays visible on KDE).
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

module="${1:-}"
script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

hidden_json() {
  emit_waybar_json "" "" "hidden"
}

compositor="$(detect_compositor)"

if [ "$compositor" != "hyprland" ]; then
  hidden_json
  exit 0
fi

case "$module" in
  notify)
    emit_waybar_json "󰂚" "Show notifications" "ready"
    ;;
  light)
    emit_waybar_json "󰃠" "Adjust brightness" "ready"
    ;;
  *)
    hidden_json
    ;;
esac
