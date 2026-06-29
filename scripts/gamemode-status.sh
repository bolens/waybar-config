#!/usr/bin/env sh
set -eu

script_dir="${0%/*}"
. "$script_dir/waybar-cache-helpers.sh"
# shellcheck source=compositor-session.sh
. "$script_dir/compositor-session.sh"

hidden_json() {
  emit_waybar_json "" "" "hidden"
}

[ "$(detect_compositor)" = "hyprland" ] || {
  hidden_json
  exit 0
}

command -v hyprctl >/dev/null 2>&1 || {
  hidden_json
  exit 0
}

enabled_raw="$(hyprctl getoption animations:enabled 2>/dev/null || true)"
enabled="1"
case "$enabled_raw" in
  *int:*0*) enabled="0" ;;
esac

blur_raw="$(hyprctl getoption decoration:blur:enabled 2>/dev/null || true)"
blur="1"
case "$blur_raw" in
  *int:*0*) blur="0" ;;
esac

if [ "$enabled" = "0" ] || [ "$blur" = "0" ]; then
  emit_waybar_json "󰊗" "Gamemode active\nAnimations/blur reduced\nClick: toggle · Right: restore defaults" "active"
else
  emit_waybar_json "󰊗" "Gamemode inactive\nClick to enable performance mode" "inactive"
fi
