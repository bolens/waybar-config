#!/usr/bin/env sh
set -eu

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
. "$script_dir/compositor-session.sh"

hidden_json() {
  jq -cn '{text:"", tooltip:"", class:"hidden"}'
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
  jq -cn '{
    text: "󰊗",
    class: "active",
    tooltip: "Gamemode active\nAnimations/blur reduced\nClick: toggle · Right: restore defaults"
  }'
else
  jq -cn '{
    text: "󰊗",
    class: "inactive",
    tooltip: "Gamemode inactive\nClick to enable performance mode"
  }'
fi
