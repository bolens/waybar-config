#!/usr/bin/env sh
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/kdeconnect-status.json"
lock_dir="$cache_dir/kdeconnect-status.lock.d"
ttl=30
stale_lock_ttl=15

mkdir -p "$cache_dir"

script_dir="${0%/*}"
. "$script_dir/waybar-cache-helpers.sh"

# Action handler: --ring
if [ "${1:-}" = "--ring" ]; then
  devices=$(timeout 2 qdbus6 org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices false true 2>/dev/null || true)
  for dev in $devices; do
    reachable=$(timeout 2 qdbus6 org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.isReachable 2>/dev/null || echo "false")
    if [ "$reachable" = "true" ]; then
      kdeconnect-cli -d "$dev" --ring >/dev/null 2>&1 || true
      exit 0
    fi
  done
  exit 0
fi


if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰏲" "Connecting to KDE Connect..." "disconnected"
  exit 0
fi

# --refresh mode
# Query devices list with timeout guard
devices=$(timeout 2 qdbus6 org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices false true 2>/dev/null || true)

primary_text="󰏲"
primary_class="disconnected"
tooltip="KDE Connect Devices\n"
has_any_device=0
has_any_reachable=0
first_reachable_dev=""
first_name=""
first_type=""
first_battery=""
first_charging=""

for dev in $devices; do
  has_any_device=1
  name=$(timeout 2 qdbus6 org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.name 2>/dev/null || echo "Unknown Device")
  reachable=$(timeout 2 qdbus6 org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.isReachable 2>/dev/null || echo "false")
  dev_type=$(timeout 2 qdbus6 org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.type 2>/dev/null || echo "phone")
  
  if [ "$reachable" = "true" ]; then
    has_any_reachable=1
    battery=$(timeout 2 qdbus6 org.kde.kdeconnect "/modules/kdeconnect/devices/$dev/battery" org.kde.kdeconnect.device.battery.charge 2>/dev/null || echo "")
    charging=$(timeout 2 qdbus6 org.kde.kdeconnect "/modules/kdeconnect/devices/$dev/battery" org.kde.kdeconnect.device.battery.isCharging 2>/dev/null || echo "false")
    
    if [ -z "$first_reachable_dev" ]; then
      first_reachable_dev="$dev"
      first_name="$name"
      first_type="$dev_type"
      first_battery="$battery"
      first_charging="$charging"
    fi
    
    battery_status=""
    if [ -n "$battery" ]; then
      battery_status="($battery%)"
      [ "$charging" = "true" ] && battery_status="($battery% 󱐋)"
    fi
    
    tooltip=$(printf '%s\n● %s (Connected) %s' "$tooltip" "$name" "$battery_status")
  else
    tooltip=$(printf '%s\n○ %s (Disconnected)' "$tooltip" "$name")
  fi
done

if [ "$has_any_device" -eq 0 ]; then
  tooltip="No paired devices found"
elif [ "$has_any_reachable" -eq 1 ] && [ -n "$first_reachable_dev" ]; then
  primary_class="connected"
  name="$first_name"
  dev_type="$first_type"
  battery="$first_battery"
  charging="$first_charging"
  
  icon="󰏲"
  if [ "$dev_type" = "tablet" ]; then
    icon="󰓏"
  fi
  
  if [ -n "$battery" ]; then
    battery_level=$(printf '%3d' "$battery")
    if [ "$charging" = "true" ]; then
      primary_text=$(printf '%s 󱐋%d%%' "$icon" "$battery")
    else
      primary_text=$(printf '%s %d%%' "$icon" "$battery")
    fi
    
    if [ "$battery" -le 15 ] && [ "$charging" != "true" ]; then
      primary_class="critical"
    elif [ "$battery" -le 30 ] && [ "$charging" != "true" ]; then
      primary_class="warning"
    fi
  else
    primary_text="$icon"
  fi
  
  tooltip=$(printf '%s\n\nLeft: ring phone (%s) · Right: KDE Connect settings · Middle: refresh' "$tooltip" "$name")
else
  primary_text="󰏲"
  primary_class="disconnected"
  tooltip=$(printf '%s\n\nLeft: ring phone (N/A) · Right: KDE Connect settings · Middle: refresh' "$tooltip")
fi

json=$(emit_waybar_json "$primary_text" "$tooltip" "$primary_class")

printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" > "$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
