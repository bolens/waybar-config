#!/usr/bin/env sh
# Sunshine Game Streaming Status module for Waybar.
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/sunshine-status.json"
lock_dir="$cache_dir/sunshine-status.lock.d"
ttl=10
stale_lock_ttl=15

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
  emit_waybar_json "󰕧 ..." "Refreshing Sunshine status in background" "disabled"
  exit 0
fi

# Check service status
service_active=0
if systemctl --user is-active -q app-dev.lizardbyte.app.Sunshine.service 2>/dev/null; then
  service_active=1
elif pgrep -x sunshine >/dev/null 2>&1; then
  service_active=1
fi

if [ "$service_active" -eq 0 ]; then
  json=$(emit_waybar_json "󰕧 Off" "Sunshine game streaming host is offline" "offline")
  printf '%s\n' "$json"
  printf '%s\n' "$json" > "$cache_file"
  exit 0
fi

# Check if client is actively streaming
# Sunshine uses UDP 47998 (Video), UDP 47999 (Audio), and TCP 48010 (RTSP) for streaming.
# If there are active connection states on these ports, a client is streaming.
streaming=0
if command -v ss >/dev/null 2>&1; then
  # Look for established connections on Sunshine streaming ports
  if ss -t -u -n -a 2>/dev/null | grep -E -q "ESTAB.*(:47998|:47999|:48010)"; then
    streaming=1
  fi
fi

# Get process information if available
pid=""
uptime_str="Unknown"
cpu_usage="0%"
if command -v ps >/dev/null 2>&1; then
  pid=$(pgrep -x sunshine | head -n 1 || true)
  if [ -n "$pid" ]; then
    cpu_usage=$(ps -p "$pid" -o %cpu= 2>/dev/null | awk '{print $1"%"}' || echo "0%")
    # Get elapsed time
    etime=$(ps -p "$pid" -o etime= 2>/dev/null | awk '{print $1}' || true)
    if [ -n "$etime" ]; then
      uptime_str="$etime"
    fi
  fi
fi

if [ "$streaming" -eq 1 ]; then
  text="󰕧 Active"
  class="warning" # Yellow highlight when streaming
  tooltip=$(printf 'Sunshine Game Stream\n\nStatus: Streaming (Client Connected)\nUptime: %s\nCPU Usage: %s\n\nLeft: open configuration UI · Right: restart service · Middle: refresh' "$uptime_str" "$cpu_usage")
else
  text="󰕧 Idle"
  class="normal" # Green/Cyan when idle and ready
  tooltip=$(printf 'Sunshine Game Stream\n\nStatus: Ready (No Client Connected)\nUptime: %s\nCPU Usage: %s\n\nLeft: open configuration UI · Right: restart service · Middle: refresh' "$uptime_str" "$cpu_usage")
fi

json=$(emit_waybar_json "$text" "$tooltip" "$class")
printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" > "$tmp_cache"
mv -f "$tmp_cache" "$cache_file"

# Signal Waybar to refresh the module UI
pkill -x -RTMIN+23 waybar >/dev/null 2>&1 || true

