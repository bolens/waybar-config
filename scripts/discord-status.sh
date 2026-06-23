#!/usr/bin/env sh
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/discord-status.json"
ttl=60

. "$HOME/.config/waybar/scripts/waybar-cache-helpers.sh"

cached="$(read_fresh_cache_file "$cache_file" "$ttl" 2>/dev/null || true)"
if [ -n "$cached" ]; then
  printf '%s\n' "$cached"
  exit 0
fi

text="󰙯"
class="offline"
tooltip=$(printf 'Discord offline\nLeft: focus · Right: mute · Middle: deafen')

if pgrep -x Discord >/dev/null 2>&1; then
  class="discord"
  tooltip=$(printf 'Discord running\nLeft: focus · Right: mute · Middle: deafen')
fi

json="$(jq -cn \
  --arg text "$text" \
  --arg tooltip "$tooltip" \
  --arg class "$class" \
  '{text:$text, tooltip:$tooltip, class:$class}')"

printf '%s\n' "$json"

tmp="$cache_file.tmp.$$"
printf '%s\n' "$json" >"$tmp"
mv -f "$tmp" "$cache_file"
