#!/usr/bin/env sh
# Hide Hyprland-only bar modules when not running Hyprland (hyprwhspr stays visible on KDE).
set -eu

module="${1:-}"
script_dir="${0%/*}"
. "$script_dir/waybar-cache-helpers.sh"
. "$script_dir/compositor-session.sh"

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
