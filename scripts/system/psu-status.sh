#!/usr/bin/env bash
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/psu-status.json"
lock_dir="$cache_dir/psu-status.lock.d"
ttl="$(waybar_module_interval psu 10)"
stale_lock_ttl=15

mkdir -p "$cache_dir"

script_dir="${0%/*}"
# Handle sourcing when run directly or by Waybar
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-locale-lib.sh"
if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󱉔 --" "Initializing PSU..." "normal"
  exit 0
fi

# --refresh mode
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
psu_temp_warn=$(waybar_settings_get '.thresholds.psu.temp.warning' '55')
psu_temp_crit=$(waybar_settings_get '.thresholds.psu.temp.critical' '65')

# Test/portability hook: fake hwmon tree via WAYBAR_HWMON_ROOT.
# Path cache (corsairpsu-path.txt) stores an absolute directory — clear that file
# when swapping roots in tests, or an old path will keep winning.
hwmon_root="${WAYBAR_HWMON_ROOT:-/sys/class/hwmon}"

# 1. Find corsairpsu hwmon path:
# Corsair digital power supplies report real-time telemetry (watts, volts, temp) via the corsairpsu driver.
# We cache the sysfs path under hwmon to avoid walking the directory tree on every refresh.
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
  for d in "$hwmon_root"/hwmon*; do
    if [ -f "$d/name" ] && [ "$(cat "$d/name" 2>/dev/null)" = "corsairpsu" ]; then
      psu_dir="$d"
      tmp_psu="$psu_path_file.tmp.$$"
      printf '%s\n' "$psu_dir" >"$tmp_psu" 2>/dev/null && mv -f "$tmp_psu" "$psu_path_file" 2>/dev/null || true
      break
    fi
  done
fi

if [ -z "$psu_dir" ]; then
  # Quietly hide/disable if not found (or return N/A)
  json=$(emit_waybar_json "" "Corsair PSU telemetry not found" "disconnected")
  printf '%s\n' "$json"
  tmp_cache="$cache_file.tmp.$$"
  printf '%s\n' "$json" >"$tmp_cache"
  mv -f "$tmp_cache" "$cache_file"
  exit 0
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

# Values from corsairpsu:
# Raw driver properties are scale integers:
#   - Power (power*_input) in microwatts (needs division by 1,000,000 to get Watts)
#   - Voltage (in*_input) in millivolts (needs division by 1,000 to get Volts)
#   - Temperature (temp*_input) in millidegrees Celsius (needs division by 1,000 to get °C)
power_total_raw=$(read_val "$psu_dir/power1_input")
power_12v_raw=$(read_val "$psu_dir/power2_input")
power_5v_raw=$(read_val "$psu_dir/power3_input")
power_33v_raw=$(read_val "$psu_dir/power4_input")

fan_rpm=$(read_val "$psu_dir/fan1_input")

temp_vrm_raw=$(read_val "$psu_dir/temp1_input")
temp_case_raw=$(read_val "$psu_dir/temp2_input")

v_in_raw=$(read_val "$psu_dir/in0_input")
v_out_12v_raw=$(read_val "$psu_dir/in1_input")
v_out_5v_raw=$(read_val "$psu_dir/in2_input")
v_out_33v_raw=$(read_val "$psu_dir/in3_input")

# Conversions
power_total=$((power_total_raw / 1000000))
v_in=$((v_in_raw / 1000))

# Consolidate scale operations into a single awk process invocation for efficiency
read -r power_12v power_5v power_33v temp_vrm temp_case v_out_12v v_out_5v v_out_33v <<EOF
$(awk -v p12="$power_12v_raw" -v p5="$power_5v_raw" -v p33="$power_33v_raw" \
  -v tvrm="$temp_vrm_raw" -v tcase="$temp_case_raw" \
  -v v12="$v_out_12v_raw" -v v5="$v_out_5v_raw" -v v33="$v_out_33v_raw" \
  'BEGIN {
        printf "%.1f %.1f %.1f %.1f %.1f %.2f %.2f %.2f\n",
          p12/1000000, p5/1000000, p33/1000000,
          tvrm/1000, tcase/1000,
          v12/1000, v5/1000, v33/1000
      }')
EOF

# Determine styling class based on VRM temp
class="normal"
vrm_int=${temp_vrm%.*}
case_int=${temp_case%.*}

if [ -n "$vrm_int" ] && [ "$vrm_int" -ge "$psu_temp_crit" ] 2>/dev/null; then
  class="critical"
elif [ -n "$vrm_int" ] && [ "$vrm_int" -ge "$psu_temp_warn" ] 2>/dev/null; then
  class="warning"
fi

vrm_formatted="N/A"
if [ -n "$vrm_int" ]; then
  vrm_formatted=$(format_locale_temp "$vrm_int")
fi

case_formatted="N/A"
if [ -n "$case_int" ]; then
  case_formatted=$(format_locale_temp "$case_int")
fi

text=$(printf '󱉔 %sW' "$power_total")

tooltip=$(printf 'Corsair Digital PSU
Total Load: %sW
  ├─ +12V Rail: %sW (%sV)
  ├─ +5V Rail: %sW (%sV)
  └─ +3.3V Rail: %sW (%sV)
Input Voltage: %sV AC
Cooling Fan: %s RPM
Temperatures:
  ├─ VRM: %s
  └─ Case: %s

Left: mission center · Right: btop · Middle: refresh' \
  "$power_total" "$power_12v" "$v_out_12v" "$power_5v" "$v_out_5v" "$power_33v" "$v_out_33v" \
  "$v_in" "$fan_rpm" "$vrm_formatted" "$case_formatted")

json=$(emit_waybar_json "$text" "$tooltip" "$class")

printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" >"$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
