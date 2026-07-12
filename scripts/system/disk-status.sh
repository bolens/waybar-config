#!/usr/bin/env bash
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/disk-status.json"
lock_dir="$cache_dir/disk-status.lock.d"
script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/gauge-lib.sh"
ttl="$(waybar_module_interval disk 60)"
stale_lock_ttl=15

mkdir -p "$cache_dir"

script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

disk_warn=$(waybar_settings_get '.thresholds.disk.warning' '75')
disk_crit=$(waybar_settings_get '.thresholds.disk.critical' '90')
disk_path=$(waybar_settings_get '.disk.path' '/')
gauges_enabled=$(waybar_settings_get '.visual.gauges.enabled' 'true')
gauge_width=$(waybar_settings_get '.visual.gauges.width' '8')

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰋊 --%" "Initializing disk stats..." "normal"
  exit 0
fi

# --refresh mode
df_info=$(df -h "$disk_path" | awk 'NR==2 {print $2, $3, $4, $5}')
set -- $df_info
size="${1:-0}"
used="${2:-0}"
avail="${3:-0}"
pct="${4:-0%}"

percent_num=$(printf '%s' "$pct" | tr -d '%')
class="$(waybar_threshold_class "$percent_num" "$disk_warn" "$disk_crit")"

text="$(gauge_status_text "󰋊" "$percent_num")"
tooltip=$(printf 'Disk Space (%s)\nTotal: %s\nUsed: %s\nAvailable: %s\nUsage: %s\n\nLeft: file manager · Right: btop · Middle: refresh' "$disk_path" "$size" "$used" "$avail" "$pct")

json=$(emit_waybar_json "$text" "$tooltip" "$class")

printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" >"$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
