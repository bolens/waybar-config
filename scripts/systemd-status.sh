#!/usr/bin/env sh
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/systemd-status.json"
lock_dir="$cache_dir/systemd-status.lock.d"
ttl=15
stale_lock_ttl=10

mkdir -p "$cache_dir"

script_dir="${0%/*}"
. "$script_dir/waybar-cache-helpers.sh"


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
  
  jq -cn --arg text "" --arg tooltip "Checking systemd health..." --arg class "hidden" \
    '{text:$text, tooltip:$tooltip, class:$class}'
  exit 0
fi

# --refresh mode
system_failed=$(timeout 2 systemctl --failed --plain --no-legend 2>/dev/null || true)
user_failed=$(timeout 2 systemctl --user --failed --plain --no-legend 2>/dev/null || true)

system_count=0
sys_list=""
if [ -n "$system_failed" ]; then
  {
    read -r system_count
    sys_list=$(cat)
  } <<EOF
$(printf '%s\n' "$system_failed" | awk '
  /\.service/ {
    count++
    list = list (list ? "\n" : "") "● " $1
  }
  END {
    print count+0
    if (list) print list
  }
')
EOF
fi

user_count=0
usr_list=""
if [ -n "$user_failed" ]; then
  {
    read -r user_count
    usr_list=$(cat)
  } <<EOF
$(printf '%s\n' "$user_failed" | awk '
  /\.service/ {
    count++
    list = list (list ? "\n" : "") "● " $1
  }
  END {
    print count+0
    if (list) print list
  }
')
EOF
fi

total=$((system_count + user_count))

if [ "$total" -eq 0 ]; then
  text=""
  class="hidden"
  tooltip="All systemd services are healthy"
else
  text=$(printf '󱄜 %d' "$total")
  class="critical"
  
  # Format service lists for tooltip
  tooltip=$(printf 'Failed Systemd Services: %d\n' "$total")
  
  if [ "$system_count" -gt 0 ]; then
    tooltip=$(printf '%s\nSystem Services:\n%s' "$tooltip" "$sys_list")
  fi
  
  if [ "$user_count" -gt 0 ]; then
    tooltip=$(printf '%s\nUser Services:\n%s' "$tooltip" "$usr_list")
  fi
  
  tooltip=$(printf '%s\n\nLeft: inspect failed · Right: settings · Middle: refresh' "$tooltip")
fi

json=$(jq -cn \
  --arg text "$text" \
  --arg tooltip "$tooltip" \
  --arg class "$class" \
  '{text:$text, tooltip:$tooltip, class:$class}')

printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" > "$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
