#!/usr/bin/env sh
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/uptime-status.json"
lock_dir="$cache_dir/uptime-status.lock.d"
script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
ttl="$(waybar_module_interval uptime 60)"
stale_lock_ttl=15

mkdir -p "$cache_dir"

script_dir="${0%/*}"

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰔚 --" "Initializing uptime..." "normal"
  exit 0
fi

# --refresh mode
read -r uptime_sec _ </proc/uptime
uptime_sec=${uptime_sec%.*}
days=$((uptime_sec / 86400))
hours=$(((uptime_sec % 86400) / 3600))
mins=$(((uptime_sec % 3600) / 60))

raw_uptime_short=""
[ "$days" -gt 0 ] && raw_uptime_short="${days}d "
[ "$hours" -gt 0 ] && raw_uptime_short="${raw_uptime_short}${hours}h "
raw_uptime_short="${raw_uptime_short}${mins}m"

raw_uptime_long=""
if [ "$days" -gt 0 ]; then
  raw_uptime_long="${days} day$([ "$days" -gt 1 ] && echo "s" || echo ""), "
fi
if [ "$hours" -gt 0 ] || [ "$days" -gt 0 ]; then
  raw_uptime_long="${raw_uptime_long}${hours} hour$([ "$hours" -ne 1 ] && echo "s" || echo ""), "
fi
raw_uptime_long="${raw_uptime_long}${mins} minute$([ "$mins" -ne 1 ] && echo "s" || echo "")"
load_avg=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
btime=$(awk '/^btime/ {print $2}' /proc/stat)
boot_time=$(format_locale_datetime "$btime")

text=$(printf '󰔚 %s' "$raw_uptime_short")
tooltip=$(printf 'System Uptime\nUptime: %s\nLoad Average: %s\nBoot Time: %s\n\nLeft: btop · Right: system monitor · Middle: refresh' "$raw_uptime_long" "$load_avg" "$boot_time")

json=$(emit_waybar_json "$text" "$tooltip" "normal")

printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" >"$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
