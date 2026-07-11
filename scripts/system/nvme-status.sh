#!/usr/bin/env bash
# Waybar status: hottest NVMe composite (or max sensor) temperature.
# Hides (disconnected) when no nvme hwmon sensors are present.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/nvme-status.json"
lock_dir="$cache_dir/nvme-status.lock.d"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
ttl="$(waybar_module_interval nvme 10)"
stale_lock_ttl=15

mkdir -p "$cache_dir"

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰋊 --" "Initializing NVMe temps..." "normal"
  exit 0
fi

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
temp_warn=$(waybar_settings_get '.thresholds.nvme.temp.warning' '60')
temp_crit=$(waybar_settings_get '.thresholds.nvme.temp.critical' '75')

write_cache_and_exit() {
  json="$1"
  printf '%s\n' "$json"
  tmp_cache="$cache_file.tmp.$$"
  if printf '%s\n' "$json" >"$tmp_cache" 2>/dev/null; then
    mv -f "$tmp_cache" "$cache_file" 2>/dev/null || rm -f "$tmp_cache" 2>/dev/null || true
  fi
  exit 0
}

emit_disconnected() {
  write_cache_and_exit "$(emit_waybar_json "" "$1" "disconnected")"
}

# Fixture hook for tests: directory of fake hwmon trees (each with name + temp*_input).
scan_root="${WAYBAR_NVME_HWMON_ROOT:-/sys/class/hwmon}"

hottest_c=-1
hottest_name=""
tooltip_lines=()
found=0

for d in "$scan_root"/hwmon*; do
  [ -d "$d" ] || continue
  [ -f "$d/name" ] || continue
  name=$(tr -d '\n' <"$d/name" 2>/dev/null || true)
  [ "$name" = "nvme" ] || continue

  # Prefer Composite label; else max of all temp*_input
  drive_c=-1
  has_composite=0
  sensors=()
  for tin in "$d"/temp*_input; do
    [ -f "$tin" ] || continue
    raw=$(tr -d '\n' <"$tin" 2>/dev/null || true)
    [ -n "$raw" ] || continue
    c=$((raw / 1000))
    lab_file="${tin%_input}_label"
    lab="temp"
    if [ -f "$lab_file" ]; then
      lab=$(tr -d '\n' <"$lab_file" 2>/dev/null || echo temp)
    fi
    sensors+=("${lab}:${c}°")
    lab_lc=$(printf '%s' "$lab" | tr '[:upper:]' '[:lower:]')
    if [ "$lab_lc" = "composite" ]; then
      drive_c=$c
      has_composite=1
    elif [ "$has_composite" -eq 0 ]; then
      if [ "$drive_c" -lt 0 ] || [ "$c" -gt "$drive_c" ]; then
        drive_c=$c
      fi
    fi
  done

  if [ "$drive_c" -lt 0 ]; then
    continue
  fi

  # Model hint from device symlink when available
  model=""
  if [ -e "$d/device/model" ]; then
    model=$(tr -d '\n' <"$d/device/model" 2>/dev/null | sed 's/[[:space:]]\+$//' || true)
  elif [ -e "$d/device/../../model" ]; then
    model=$(tr -d '\n' <"$d/device/../../model" 2>/dev/null | sed 's/[[:space:]]\+$//' || true)
  fi
  title="${model:-nvme}"
  found=1
  sensor_txt=$(IFS=', '; echo "${sensors[*]}")
  tooltip_lines+=("$title: ${drive_c}°C ($sensor_txt)")

  if [ "$drive_c" -gt "$hottest_c" ]; then
    hottest_c=$drive_c
    hottest_name="$title"
  fi
done

if [ "$found" -eq 0 ] || [ "$hottest_c" -lt 0 ]; then
  emit_disconnected "No NVMe temperature sensors"
fi

class="normal"
if [ "$hottest_c" -ge "$temp_crit" ] 2>/dev/null; then
  class="critical"
elif [ "$hottest_c" -ge "$temp_warn" ] 2>/dev/null; then
  class="warning"
fi

text=$(printf '󰋊 %d°' "$hottest_c")
tooltip=$(printf 'NVMe temperatures\n\nHottest: %s (%d°C)\n\n%s\n\nMiddle: refresh' \
  "$hottest_name" "$hottest_c" "$(printf '%s\n' "${tooltip_lines[@]}")")

write_cache_and_exit "$(emit_waybar_json "$text" "$tooltip" "$class")"
