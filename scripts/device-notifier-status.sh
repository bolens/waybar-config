#!/usr/bin/env sh
# Device Notifier status retrieval wrapper matching the Waybar cache pattern.
set -eu
script_dir="${0%/*}"
. "$script_dir/waybar-cache-helpers.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/device-notifier-status.json"
lock_dir="$cache_dir/device-notifier-status.lock.d"
ttl="$(waybar_module_interval device_notifier 60)"
stale_lock_ttl=10

mkdir -p "$cache_dir"

script_dir="${0%/*}"
if [ -f "$script_dir/waybar-cache-helpers.sh" ]; then
  . "$script_dir/waybar-cache-helpers.sh"
else
  . "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-cache-helpers.sh"
fi

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "" "Scanning devices..." "empty"
  exit 0
fi

# --refresh mode
json=$("$script_dir/device-notifier.py" --status)
printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" > "$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
