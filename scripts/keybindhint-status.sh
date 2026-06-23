#!/usr/bin/env sh
set -eu

script_dir="${0%/*}"

"$script_dir/compositor-gate.sh" --show hyprland -- \
  jq -cn '{text:"󰌌", class:"ready", tooltip:"Keybind cheatsheet · click to open"}' \
  || jq -cn '{text:"", tooltip:"", class:"hidden"}'
