#!/usr/bin/env sh
# KDE / Plasma notification bell for Waybar (one-shot; listener keeps cache warm).
set -eu

script_dir="${0%/*}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/notifications-status.json"
cache_ttl=120

# shellcheck source=waybar-cache-helpers.sh
. "$script_dir/waybar-cache-helpers.sh"
# shellcheck source=notifications-lib.sh
. "$script_dir/notifications-lib.sh"

if [ -f "$cache_file" ]; then
  cat "$cache_file"
  exit 0
fi

if ! pgrep -x plasmashell >/dev/null 2>&1; then
  printf '{"text":"󰂚","class":"unknown","tooltip":"plasmashell is not running"}\n'
  exit 0
fi

if kde_notifications_inhibited; then
  printf '{"text":"","class":"dnd-none","alt":"dnd-none","tooltip":"Do not disturb"}\n'
else
  printf '{"text":"","class":"none","alt":"none","tooltip":"Notifications"}\n'
fi
