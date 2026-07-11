#!/usr/bin/env sh
# Stream Deck UI Status module for Waybar.
set -eu
script_dir="${0%/*}"
. "$script_dir/waybar-cache-helpers.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/streamdeck-status.json"
lock_dir="$cache_dir/streamdeck-status.lock.d"
ttl="$(waybar_module_interval streamdeck 30)"
stale_lock_ttl=20

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
  emit_waybar_json "󰓎 ..." "Refreshing Stream Deck status in background" "disabled"
  exit 0
fi

# Check if streamdeck UI process is running
process_active=0
if pgrep -f "streamdeck" >/dev/null 2>&1; then
  process_active=1
fi

# Check for Elgato USB devices
usb_info=""
if command -v lsusb >/dev/null 2>&1; then
  usb_info=$(lsusb | grep -i "elgato" || true)
fi

# Extract connected device names
device_count=0
devices=""
if [ -n "$usb_info" ]; then
  # Parse devices
  device_count=$(printf '%s\n' "$usb_info" | grep -c -v '^$' || echo 0)
  devices=$(printf '%s\n' "$usb_info" | sed -E 's/.*ID [0-9a-fA-F:]+ //g' | sed -E 's/Systems GmbH //g' | paste -sd "," - || true)
fi

# Process system info
pid=""
cpu_usage="0%"
mem_usage="0M"
if [ "$process_active" -eq 1 ] && command -v ps >/dev/null 2>&1; then
  pid=$(pgrep -f "streamdeck" | head -n 1 || true)
  if [ -n "$pid" ]; then
    cpu_usage=$(ps -p "$pid" -o %cpu= 2>/dev/null | awk '{print $1"%"}' || echo "0%")
    rss=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{print $1}' || echo "0")
    if [ "$rss" -gt 0 ] 2>/dev/null; then
      mem_usage=$(printf "%.1fM\n" "$(echo "$rss / 1024" | bc -l 2>/dev/null || echo "0")")
    fi
  fi
fi

# Define display state
if [ "$process_active" -eq 0 ]; then
  text="󰓎 Off"
  class="offline"
  tooltip=$(printf 'Stream Deck UI\n\nDaemon: Offline\nConnected Hardware: %s\n\nLeft: start daemon · Right: open settings UI · Middle: refresh' \
    "$( [ -n "$devices" ] && printf '%s' "$devices" || printf 'None' )")
elif [ "$device_count" -eq 0 ]; then
  text="󰓎 No Dev"
  class="warning"
  tooltip=$(printf 'Stream Deck UI\n\nDaemon: Active (PID: %s)\nConnected Hardware: None\nCPU: %s | Memory: %s\n\nLeft: open configuration UI · Right: restart service · Middle: refresh' \
    "$pid" "$cpu_usage" "$mem_usage")
else
  # Shorten device text for status bar if possible
  dev_short="On"
  if echo "$devices" | grep -qi "XL"; then
    dev_short="XL"
  elif echo "$devices" | grep -qi "Pedal"; then
    dev_short="Pedal"
  elif echo "$devices" | grep -qi "Mini"; then
    dev_short="Mini"
  fi
  text="󰓎 $dev_short"
  class="normal"
  tooltip=$(printf 'Stream Deck UI\n\nDaemon: Active (PID: %s)\nConnected Hardware: %s\nCPU: %s | Memory: %s\n\nLeft: open configuration UI · Right: restart service · Middle: refresh' \
    "$pid" "$devices" "$cpu_usage" "$mem_usage")
fi

json=$(emit_waybar_json "$text" "$tooltip" "$class")
printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" > "$tmp_cache"
mv -f "$tmp_cache" "$cache_file"

# Signal Waybar to refresh the module UI
pkill -x -RTMIN+24 waybar >/dev/null 2>&1 || true

