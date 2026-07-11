#!/usr/bin/env bash
set -eu
script_dir="${0%/*}"
. "$script_dir/waybar-cache-helpers.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/fans-status.json"
lock_dir="$cache_dir/fans-status.lock.d"
ttl="$(waybar_module_interval fans 10)"
stale_lock_ttl=15

mkdir -p "$cache_dir"

script_dir="${0%/*}"
# Handle sourcing when run directly or by Waybar
if [ -f "$script_dir/waybar-cache-helpers.sh" ]; then
  . "$script_dir/waybar-cache-helpers.sh"
else
  . "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-cache-helpers.sh"
fi
. "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-settings.sh"
fan_cpu_warn=$(waybar_settings_get '.thresholds.fans.cpu.warning' '1600')
fan_cpu_crit=$(waybar_settings_get '.thresholds.fans.cpu.critical' '2000')
fan_gpu_warn=$(waybar_settings_get '.thresholds.fans.gpu.warning' '70')
fan_gpu_crit=$(waybar_settings_get '.thresholds.fans.gpu.critical' '85')


if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰈐 --" "Initializing cooling stats..." "normal"
  exit 0
fi

# --refresh mode

# 1. Discover asusec (Motherboard fan controller via ASUS Embedded Controller driver):
# Traverses Linux Hardware Monitoring (hwmon) sysfs interfaces.
# We cache the discovered directory path to avoid repeating loop lookups.
asusec_path_file="$cache_dir/asusec-path.txt"
asusec_dir=""
if [ -f "$asusec_path_file" ]; then
  asusec_dir=$(cat "$asusec_path_file" 2>/dev/null || true)
  if [ -n "$asusec_dir" ] && [ -d "$asusec_dir" ]; then
    if [ ! -f "$asusec_dir/name" ] || [ "$(cat "$asusec_dir/name" 2>/dev/null)" != "asusec" ]; then
      asusec_dir=""
    fi
  else
    asusec_dir=""
  fi
fi
if [ -z "$asusec_dir" ]; then
  for d in /sys/class/hwmon/hwmon*; do
    if [ -f "$d/name" ] && [ "$(cat "$d/name" 2>/dev/null)" = "asusec" ]; then
      asusec_dir="$d"
      tmp_asusec="$asusec_path_file.tmp.$$"
      printf '%s\n' "$asusec_dir" >"$tmp_asusec" 2>/dev/null && mv -f "$tmp_asusec" "$asusec_path_file" 2>/dev/null || true
      break
    fi
  done
fi

# 2. Discover corsairpsu (Corsair Power Supply sensors driver):
# Reads Corsair digital PSU hardware stats (like fan speed and voltages) via hwmon.
psu_path_file="$cache_dir/corsairpsu-path.txt"
psu_dir=""
if [ -f "$psu_path_file" ]; then
  psu_dir=$(cat "$psu_path_file" 2>/dev/null || true)
  if [ -n "$psu_dir" ] && [ -d "$psu_dir" ]; then
    if [ ! -f "$psu_dir/name" ] || [ "$(cat "$psu_dir/name" 2>/dev/null)" != "corsairpsu" ]; then
      psu_dir=""
    fi
  else
    psu_dir=""
  fi
fi
if [ -z "$psu_dir" ]; then
  for d in /sys/class/hwmon/hwmon*; do
    if [ -f "$d/name" ] && [ "$(cat "$d/name" 2>/dev/null)" = "corsairpsu" ]; then
      psu_dir="$d"
      tmp_psu="$psu_path_file.tmp.$$"
      printf '%s\n' "$psu_dir" >"$tmp_psu" 2>/dev/null && mv -f "$tmp_psu" "$psu_path_file" 2>/dev/null || true
      break
    fi
  done
fi

# Helper to read sysfs attributes (return 0 if missing)
read_val() {
  file="$1"
  if [ -f "$file" ]; then
    cat "$file" 2>/dev/null || printf '0'
  else
    printf '0'
  fi
}

cpu_fan=0
cpu_fan_label="CPU Cooler"
if [ -n "$asusec_dir" ]; then
  cpu_fan=$(read_val "$asusec_dir/fan1_input")
  cpu_fan_label=$(read_val "$asusec_dir/fan1_label")
fi

psu_fan=-1
if [ -n "$psu_dir" ]; then
  psu_fan=$(read_val "$psu_dir/fan1_input")
fi

# 3. Read GPU fan speed from system-metrics cache
gpu_fan=-1
metrics_file="$cache_dir/system-metrics.json"
if [ -f "$metrics_file" ]; then
  # Extract gpu.fan
  gpu_fan=$(jq -r '.gpu.fan // -1' "$metrics_file" 2>/dev/null || printf '-1')
fi

# Format values
text="󰈐 ${cpu_fan} RPM"

tooltip="System Cooling Status"
if [ "$cpu_fan" -gt 0 ]; then
  tooltip=$(printf '%s\n  ├─ %s: %s RPM' "$tooltip" "${cpu_fan_label:-CPU Cooler}" "$cpu_fan")
else
  tooltip=$(printf '%s\n  ├─ CPU Cooler: 0 RPM' "$tooltip")
fi

if [ "$gpu_fan" -ge 0 ]; then
  tooltip=$(printf '%s\n  ├─ GPU Fan Speed: %d%%' "$tooltip" "$gpu_fan")
else
  tooltip=$(printf '%s\n  ├─ GPU Fan: N/A' "$tooltip")
fi

if [ "$psu_fan" -ge 0 ]; then
  tooltip=$(printf '%s\n  └─ PSU Fan Speed: %d RPM' "$tooltip" "$psu_fan")
else
  tooltip=$(printf '%s\n  └─ PSU Fan: N/A' "$tooltip")
fi

tooltip=$(printf '%s\n\nLeft: nvtop · Right: btop · Middle: refresh' "$tooltip")

# Style classes based on RPM/percentage limits
class="normal"
if [ "$cpu_fan" -ge "$fan_cpu_crit" ] 2>/dev/null || [ "$gpu_fan" -ge "$fan_gpu_crit" ] 2>/dev/null; then
  class="critical"
elif [ "$cpu_fan" -ge "$fan_cpu_warn" ] 2>/dev/null || [ "$gpu_fan" -ge "$fan_gpu_warn" ] 2>/dev/null; then
  class="warning"
fi

json=$(emit_waybar_json "$text" "$tooltip" "$class")

printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" > "$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
