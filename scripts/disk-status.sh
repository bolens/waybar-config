#!/usr/bin/env sh
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/disk-status.json"
lock_dir="$cache_dir/disk-status.lock.d"
ttl=60
stale_lock_ttl=15

mkdir -p "$cache_dir"

script_dir="${0%/*}"
. "$script_dir/waybar-cache-helpers.sh"
. "$script_dir/waybar-settings.sh"

disk_warn=$(waybar_settings_get '.thresholds.disk.warning' '75')
disk_crit=$(waybar_settings_get '.thresholds.disk.critical' '90')


if [ "${1:-}" != "--refresh" ]; then
  if [ -f "$cache_file" ] && [ "$(cache_file_age "$cache_file")" -le "$ttl" ] 2>/dev/null; then
    cat "$cache_file"
    exit 0
  fi
  
  cleanup_stale_lock_dir "$lock_dir" "$stale_lock_ttl"
  [ -d "$lock_dir" ] || refresh_in_background
  
  if [ -f "$cache_file" ]; then
    cat "$cache_file"
    exit 0
  fi
  
  emit_waybar_json "󰋊 --%" "Initializing disk stats..." "normal"
  exit 0
fi

# --refresh mode
df_info=$(df -h / | awk 'NR==2 {print $2, $3, $4, $5}')
set -- $df_info
size="${1:-0}"
used="${2:-0}"
avail="${3:-0}"
pct="${4:-0%}"

percent_num=$(printf '%s' "$pct" | tr -d '%')
class="normal"
if [ "$percent_num" -ge "$disk_crit" ] 2>/dev/null; then
  class="critical"
elif [ "$percent_num" -ge "$disk_warn" ] 2>/dev/null; then
  class="warning"
fi

text=$(printf '󰋊 %3d%%' "$percent_num")
tooltip=$(printf 'Disk Space (/)\nTotal: %s\nUsed: %s\nAvailable: %s\nUsage: %s\n\nLeft: file manager · Right: btop · Middle: refresh' "$size" "$used" "$avail" "$pct")

json=$(emit_waybar_json "$text" "$tooltip" "$class")

printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" > "$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
