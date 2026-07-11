#!/usr/bin/env bash
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/fans-status.json"
lock_dir="$cache_dir/fans-status.lock.d"
ttl="$(waybar_module_interval fans 10)"
stale_lock_ttl=15

mkdir -p "$cache_dir"

script_dir="${0%/*}"
# Handle sourcing when run directly or by Waybar
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰈐 --" "Initializing cooling stats..." "normal"
  exit 0
fi

# --refresh mode
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
fan_cpu_warn=$(waybar_settings_get '.thresholds.fans.cpu.warning' '1600')
fan_cpu_crit=$(waybar_settings_get '.thresholds.fans.cpu.critical' '2000')
fan_gpu_warn=$(waybar_settings_get '.thresholds.fans.gpu.warning' '70')
fan_gpu_crit=$(waybar_settings_get '.thresholds.fans.gpu.critical' '85')

# Test hook: point at a fake hwmon tree (see scripts/ci/tests/generator/).
hwmon_root="${WAYBAR_HWMON_ROOT:-/sys/class/hwmon}"

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
  for d in "$hwmon_root"/hwmon*; do
    if [ -f "$d/name" ] && [ "$(cat "$d/name" 2>/dev/null)" = "asusec" ]; then
      asusec_dir="$d"
      tmp_asusec="$asusec_path_file.tmp.$$"
      printf '%s\n' "$asusec_dir" >"$tmp_asusec" 2>/dev/null && mv -f "$tmp_asusec" "$asusec_path_file" 2>/dev/null || true
      break
    fi
  done
fi

# 2. Discover corsairpsu — only if PSU module is unavailable (avoid duplicate fan RPM).
# When corsairpsu hwmon exists, custom/psu owns PSU fan/rails; fans notes a pointer instead.
psu_path_file="$cache_dir/corsairpsu-path.txt"
psu_dir=""
psu_covered_by_module=0
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
  for d in "$hwmon_root"/hwmon*; do
    if [ -f "$d/name" ] && [ "$(cat "$d/name" 2>/dev/null)" = "corsairpsu" ]; then
      psu_dir="$d"
      tmp_psu="$psu_path_file.tmp.$$"
      printf '%s\n' "$psu_dir" >"$tmp_psu" 2>/dev/null && mv -f "$tmp_psu" "$psu_path_file" 2>/dev/null || true
      break
    fi
  done
fi
# Prefer dedicated PSU module when corsairpsu is present (richer rails/temps).
if [ -n "$psu_dir" ]; then
  psu_covered_by_module=1
fi

# 2b. Optional nct6799 (or similar Super-IO) chassis fan enrichment via sysfs.
chassis_path_file="$cache_dir/nct6799-path.txt"
chassis_dir=""
if [ -f "$chassis_path_file" ]; then
  chassis_dir=$(cat "$chassis_path_file" 2>/dev/null || true)
  if [ -n "$chassis_dir" ] && [ -d "$chassis_dir" ]; then
    if [ ! -f "$chassis_dir/name" ] || [ "$(cat "$chassis_dir/name" 2>/dev/null)" != "nct6799" ]; then
      chassis_dir=""
    fi
  else
    chassis_dir=""
  fi
fi
if [ -z "$chassis_dir" ]; then
  for d in "$hwmon_root"/hwmon*; do
    if [ -f "$d/name" ] && [ "$(cat "$d/name" 2>/dev/null)" = "nct6799" ]; then
      chassis_dir="$d"
      tmp_ch="$chassis_path_file.tmp.$$"
      printf '%s\n' "$chassis_dir" >"$tmp_ch" 2>/dev/null && mv -f "$tmp_ch" "$chassis_path_file" 2>/dev/null || true
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

# PSU fan only when no dedicated PSU module (corsairpsu absent).
psu_fan=-1
if [ "$psu_covered_by_module" -eq 0 ] && [ -n "$psu_dir" ]; then
  psu_fan=$(read_val "$psu_dir/fan1_input")
fi

# Chassis: max spinning fan from nct6799 (no labels on many boards).
chassis_fan=-1
if [ -n "$chassis_dir" ]; then
  chassis_max=0
  for fi in "$chassis_dir"/fan*_input; do
    [ -f "$fi" ] || continue
    v=$(read_val "$fi")
    if [ "${v:-0}" -gt "$chassis_max" ] 2>/dev/null; then
      chassis_max=$v
    fi
  done
  if [ "$chassis_max" -gt 0 ] 2>/dev/null; then
    chassis_fan=$chassis_max
  fi
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

if [ "$chassis_fan" -ge 0 ]; then
  tooltip=$(printf '%s\n  ├─ Chassis (nct6799 max): %d RPM' "$tooltip" "$chassis_fan")
fi

if [ "$psu_covered_by_module" -eq 1 ]; then
  tooltip=$(printf '%s\n  └─ PSU Fan: see PSU module (corsairpsu)' "$tooltip")
elif [ "$psu_fan" -ge 0 ]; then
  tooltip=$(printf '%s\n  └─ PSU Fan Speed: %d RPM' "$tooltip" "$psu_fan")
else
  tooltip=$(printf '%s\n  └─ PSU Fan: N/A' "$tooltip")
fi

# fanctl: note when a userspace fan controller is installed / configured (does not replace hwmon).
fanctl_note=""
if command -v fanctl >/dev/null 2>&1 || [ -n "${WAYBAR_FANCTL_BIN:-}" ]; then
  fanctl_cfg=""
  for c in \
    "${WAYBAR_FANCTL_CONFIG:-}" \
    "$HOME/.config/fanctl/fanctl.yml" \
    "$HOME/.config/fanctl.yml" \
    /etc/fanctl.yml \
    /etc/fanctl/fanctl.yml; do
    [ -n "$c" ] && [ -f "$c" ] && fanctl_cfg="$c" && break
  done
  if [ -n "$fanctl_cfg" ]; then
    fanctl_note=$(printf 'fanctl config: %s' "$fanctl_cfg")
  else
    fanctl_note="fanctl installed (no config found)"
  fi
  tooltip=$(printf '%s\n\n%s' "$tooltip" "$fanctl_note")
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
printf '%s\n' "$json" >"$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
