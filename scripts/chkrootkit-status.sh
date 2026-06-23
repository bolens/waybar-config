#!/usr/bin/env sh
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/chkrootkit-status.json"
lock_dir="$cache_dir/chkrootkit-status.lock.d"
ttl=15
stale_lock_ttl=20

mkdir -p "$cache_dir"

script_dir="${0%/*}"
# Handle sourcing when run directly or by Waybar
if [ -f "$script_dir/waybar-cache-helpers.sh" ]; then
  . "$script_dir/waybar-cache-helpers.sh"
else
  . "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-cache-helpers.sh"
fi


if [ "${1:-}" != "--refresh" ]; then
  # Check if scan is running
  active_state=$(timeout 2 systemctl show -p ActiveState chkrootkit-scan.service 2>/dev/null | awk -F= '{print $2}')
  if [ "$active_state" = "active" ] || [ "$active_state" = "activating" ]; then
    # shellcheck source=unicode-animations-lib.sh
    . "$script_dir/unicode-animations-lib.sh"
    
    # Load last scan date to show in tooltip
    last_scan_date="N/A"
    stamp_file="/var/lib/systemd/timers/stamp-chkrootkit-scan.timer"
    if [ -f "$stamp_file" ]; then
      last_scan_date=$(format_locale_datetime "$(stat -c %Y "$stamp_file")")
    fi
    
    frame=0
    for i in $(seq 1 75); do # 75 * 0.2s = 15s
      if [ $((i % 25)) -eq 0 ]; then
        state=$(timeout 2 systemctl show -p ActiveState chkrootkit-scan.service 2>/dev/null | awk -F= '{print $2}')
        if [ "$state" != "active" ] && [ "$state" != "activating" ]; then
          # Scan finished! Break loop to let the script write final cache
          break
        fi
      fi
      spinner=$(get_anim_frame "dots" "$frame")
      jq -cn \
        --arg text "$spinner Chkroot" \
        --arg tooltip "chkrootkit Rootkit Scanner\nStatus: Scanning...\nLast Scan: $last_scan_date\n\nScan is running in background..." \
        --arg class "scanning" \
        '{text:$text, tooltip:$tooltip, class:$class}'
      frame=$((frame + 1))
      sleep 0.2
    done
    
    # Trigger refresh to write final state to cache
    "$script_dir/chkrootkit-status.sh" --refresh >/dev/null 2>&1 &
    exit 0
  fi

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
  
  jq -cn --arg text "󰖳 Chkroot" --arg tooltip "Checking chkrootkit..." --arg class "normal" \
    '{text:$text, tooltip:$tooltip, class:$class}'
  exit 0
fi

# --refresh mode
stamp_file="/var/lib/systemd/timers/stamp-chkrootkit-scan.timer"
elapsed=-1
if [ -f "$stamp_file" ]; then
  last_scan_time=$(stat -c %Y "$stamp_file")
  last_scan_date=$(format_locale_datetime "$last_scan_time")
  now=$(date +%s)
  elapsed=$((now - last_scan_time))
  if [ "$elapsed" -lt 60 ]; then
    ago="${elapsed}s ago"
  elif [ "$elapsed" -lt 3600 ]; then
    ago="$((elapsed / 60))m ago"
  elif [ "$elapsed" -lt 86400 ]; then
    ago="$((elapsed / 3600))h ago"
  else
    ago="$((elapsed / 86400))d ago"
  fi
else
  last_scan_date="Never"
  ago="N/A"
fi

active_state="inactive"
result_state="success"
exit_code="0"

while IFS='=' read -r key val; do
  case "$key" in
    ActiveState) active_state="$val" ;;
    Result) result_state="$val" ;;
    ExecMainStatus) exit_code="$val" ;;
  esac
done <<EOF
$(timeout 2 systemctl show -p ActiveState -p Result -p ExecMainStatus chkrootkit-scan.service 2>/dev/null)
EOF

status_text="Inactive"
class="normal"
icon="󰱠" # shield-check

if [ "$active_state" = "active" ] || [ "$active_state" = "activating" ]; then
  status_text="Scanning"
  class="scanning"
  icon="󰑐" # loading/spinning icon
elif [ "$result_state" = "failed" ] || { [ -n "$exit_code" ] && [ "$exit_code" -ne 0 ] 2>/dev/null; }; then
  status_text="Failed / Threat Found"
  class="critical"
  icon="󰦃" # shield-alert
elif [ "$elapsed" -eq -1 ]; then
  status_text="Never Scanned"
  class="warning"
  icon="󰒃"
elif [ "$elapsed" -gt 86400 ]; then # 24 hours
  status_text="Scan Stale (> 24 hours)"
  class="warning"
  icon="󰒃"
fi

text=$(printf '%s Chkroot' "$icon")
tooltip=$(printf 'chkrootkit Rootkit Scanner
Status: %s
Last Scan: %s (%s)
Result: %s

Left: start daily scan · Right: view service logs · Middle: refresh' \
  "$status_text" "$last_scan_date" "$ago" "$result_state")

json=$(jq -cn \
  --arg text "$text" \
  --arg tooltip "$tooltip" \
  --arg class "$class" \
  '{text:$text, tooltip:$tooltip, class:$class}')

printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" > "$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
