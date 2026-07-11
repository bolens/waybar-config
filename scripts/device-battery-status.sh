#!/usr/bin/env bash
set -eu
script_dir="${0%/*}"
. "$script_dir/waybar-cache-helpers.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/device-battery.json"
lock_dir="$cache_dir/device-battery.lock.d"
ttl="$(waybar_module_interval device_battery 30)"
stale_lock_ttl=45

mkdir -p "$cache_dir"

script_dir="${0%/*}"
# Handle sourcing when run directly or by Waybar
if [ -f "$script_dir/waybar-cache-helpers.sh" ]; then
  . "$script_dir/waybar-cache-helpers.sh"
else
  . "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-cache-helpers.sh"
fi
if [ -f "$script_dir/waybar-settings.sh" ]; then
  . "$script_dir/waybar-settings.sh"
else
  . "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-settings.sh"
fi

batt_warn=$(waybar_settings_get '.thresholds.device_battery.warning' '30')
batt_crit=$(waybar_settings_get '.thresholds.device_battery.critical' '15')

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  # Hide by default until first check completes
  emit_waybar_json "" "Initializing device battery..." "none"
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
  json=$(emit_waybar_json "" "No wireless devices connected" "none")
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
elif [ "$capacity" -le "$batt_crit" ]; then
  class="critical"
elif [ "$capacity" -le "$batt_warn" ]; then
  class="warning"
fi

text=$(printf '%s %d%%' "$icon" "$capacity")
tooltip=$(printf 'Device Battery: %s\nLevel: %d%%\nStatus: %s\n\nLeft: Solaar · Right: input settings · Middle: refresh' "$model_name" "$capacity" "$status")

json=$(emit_waybar_json "$text" "$tooltip" "$class")

printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" > "$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
