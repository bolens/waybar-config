#!/usr/bin/env sh
# KDE Vaults status retrieval wrapper matching the Waybar cache pattern.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/vaults-status.json"
lock_dir="$cache_dir/vaults-status.lock.d"
ttl="$(waybar_module_interval vaults 60)"
stale_lock_ttl=10

mkdir -p "$cache_dir"

script_dir="${0%/*}"
if [ -f "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh" ]; then
  . "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
else
  . "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
fi

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "" "Checking vaults..." "empty"
  exit 0
fi

# --refresh mode
json=$("$script_dir/vaults.py" --status)
printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" >"$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
