#!/usr/bin/env bash
# Mako notification bell for Waybar on Hyprland (long-running).
set -eu

script_dir="${0%/*}"
# shellcheck source=notifications-lib.sh
. "$script_dir/notifications-lib.sh"

print_mako_status() {
  count="$(mako_visible_count)"
  dnd=""

  if mako_dnd_active; then
    dnd="dnd-"
  fi

  if [ "${count:-0}" -gt 0 ] 2>/dev/null; then
    alt="${dnd}notification"
    tooltip="$count active notification(s)"
    text="$count"
  else
    alt="${dnd}none"
    tooltip="No notifications"
    text=""
  fi

  if mako_dnd_active; then
    tooltip="${tooltip} · Do not disturb"
  fi

  jq -cn \
    --arg text "$text" \
    --arg alt "$alt" \
    --arg class "$alt" \
    --arg tooltip "$tooltip" \
    '{text:$text, alt:$alt, class:$class, tooltip:$tooltip}'
}

if ! command -v makoctl >/dev/null 2>&1; then
  printf '{"text":"󰂚","class":"unknown","tooltip":"makoctl not found"}\n'
  exit 0
fi

print_mako_status

while true; do
  sleep 2
  print_mako_status
done
