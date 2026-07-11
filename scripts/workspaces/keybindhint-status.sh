#!/usr/bin/env sh
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"

"$WAYBAR_SCRIPTS/lib/compositor-gate.sh" --show hyprland -- \
  jq -cn '{text:"󰌌", class:"ready", tooltip:"Keybind cheatsheet · click to open"}' \
  || jq -cn '{text:"", tooltip:"", class:"hidden"}'
