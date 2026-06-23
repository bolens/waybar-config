#!/usr/bin/env sh
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/device-battery.json"
lock_dir="$cache_dir/device-battery.lock.d"
ttl=30
stale_lock_ttl=45

mkdir -p "$cache_dir"

script_dir="${0%/*}"
# Handle sourcing when run directly or by Waybar
if [ -f "$script_dir/waybar-cache-helpers.sh" ]; then
  . "$script_dir/waybar-cache-helpers.sh"
else
  . "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-cache-helpers.sh"
fi


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
  
  # Hide by default until first check completes
  jq -cn --arg text "" --arg tooltip "Initializing device battery..." --arg class "none" \
    '{text:$text, tooltip:$tooltip, class:$class}'
  exit 0
fi

# --refresh mode
# Find a device battery under /sys/class/power_supply
dev_dir=""
for d in /sys/class/power_supply/*; do
  [ -d "$d" ] || continue
  # Ignore system batteries/AC adapters
  type=$(cat "$d/type" 2>/dev/null || true)
  scope=$(cat "$d/scope" 2>/dev/null || true)
  if [ "$type" = "Battery" ] && [ "$scope" = "Device" ]; then
    dev_dir="$d"
    break
  fi
done

if [ -z "$dev_dir" ]; then
  # No device battery found, output empty to hide the widget in Waybar
  json=$(jq -cn --arg text "" --arg tooltip "No wireless devices connected" --arg class "none" \
    '{text:$text, tooltip:$tooltip, class:$class}')
  printf '%s\n' "$json"
  tmp_cache="$cache_file.tmp.$$"
  printf '%s\n' "$json" > "$tmp_cache"
  mv -f "$tmp_cache" "$cache_file"
  exit 0
fi

capacity=$(cat "$dev_dir/capacity" 2>/dev/null || echo 0)
status=$(cat "$dev_dir/status" 2>/dev/null || echo "unknown")
model_name=$(cat "$dev_dir/model_name" 2>/dev/null || echo "Wireless Device")

# Choose icon based on model_name
icon="󰂁" # default device battery
case "$(echo "$model_name" | tr '[:upper:]' '[:lower:]')" in
  *mouse*|*g502*|*g903*|*g305*|*g603*|*g703*|*g900*|*viper*|*deathadder*|*basilisk*|*trackball*)
    icon="󰍽" # Mouse
    ;;
  *keyboard*|*g915*|*g613*|*keychron*)
    icon="󰌌" # Keyboard
    ;;
  *controller*|*gamepad*|*joystick*|*xbox*|*dualsense*|*dualshock*|*nintendo*|*sony*)
    icon="󰖺" # Gamepad
    ;;
esac

# Class selection
class="normal"
if [ "$status" = "Charging" ]; then
  class="charging"
elif [ "$capacity" -le 15 ]; then
  class="critical"
elif [ "$capacity" -le 30 ]; then
  class="warning"
fi

text=$(printf '%s %d%%' "$icon" "$capacity")
tooltip=$(printf 'Device Battery: %s\nLevel: %d%%\nStatus: %s\n\nLeft: Solaar · Right: input settings · Middle: refresh' "$model_name" "$capacity" "$status")

json=$(jq -cn \
  --arg text "$text" \
  --arg tooltip "$tooltip" \
  --arg class "$class" \
  '{text:$text, tooltip:$tooltip, class:$class}')

printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" > "$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
