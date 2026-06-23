#!/usr/bin/env sh
# Standalone system tab script for Waybar custom module
set -eu

script_dir="$(dirname "$0")"
. "$script_dir/side-info-helpers.sh"
. "$script_dir/side-info-cache.sh"
. "$script_dir/waybar-cache-helpers.sh"
. "$script_dir/side-info-system-summary.sh"

stale_lock_ttl=30

cache_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-side-graphs/cache"
lock_dir="$cache_dir/system-refresh.lock.d"
cache_file="$(cache_file_for "$cache_dir" system)"
ttl="$(cache_ttl_for system)"

mkdir -p "$cache_dir"


if [ "${1:-}" = "--refresh" ]; then
	system_summary
	exit 0
fi

age="$(cache_file_age "$cache_file")"
if [ "$age" -le "$ttl" ] 2>/dev/null; then
	bar_json_from_system_summary "$(cat "$cache_file")"
	exit 0
fi

cleanup_stale_lock_dir "$lock_dir" "$stale_lock_ttl"

[ -d "$lock_dir" ] || refresh_in_background

if [ -f "$cache_file" ]; then
	bar_json_from_system_summary "$(cat "$cache_file")"
	exit 0
fi

emit_line "󰍛 ..." "Collecting system summary in background" "disabled"
