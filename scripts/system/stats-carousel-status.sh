#!/usr/bin/env bash
# Rotate cpu/memory/disk/gpu into one Waybar module; scroll cycles the active metric.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
. "$WAYBAR_SCRIPTS/lib/gauge-lib.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-locale-lib.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
mkdir -p "$cache_dir"
index_file="$cache_dir/stats-carousel.index"
cache_file="$cache_dir/stats-carousel.json"

modules=$(waybar_settings_get '.visual.stats_carousel.modules' '')
# waybar_settings_get uses jq -r; arrays print as JSON (not one element per line).
if printf '%s' "$modules" | jq -e 'type == "array"' >/dev/null 2>&1; then
  modules=$(printf '%s' "$modules" | jq -r '.[]')
elif [ -z "$modules" ] || [ "$modules" = "null" ]; then
  modules=$(printf '%s\n' cpu memory disk gpu)
fi
modules=$(printf '%s\n' "$modules" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;/^$/d')
if [ -z "$modules" ]; then
  modules=$(printf '%s\n' cpu memory disk gpu)
fi
mod_count=$(printf '%s\n' "$modules" | grep -c . || true)
[ "${mod_count:-0}" -ge 1 ] || mod_count=1

read_index() {
  idx=0
  if [ -f "$index_file" ]; then
    idx=$(sed -n '1p' "$index_file" 2>/dev/null || printf '0')
  fi
  case "$idx" in '' | *[!0-9]*) idx=0 ;; esac
  idx=$((idx % mod_count))
  printf '%s' "$idx"
}

write_index() {
  printf '%s\n' "$1" >"$index_file"
}

signal_refresh() {
  sig=$(waybar_settings_get '.signals.stats_carousel' '32')
  case "$sig" in '' | *[!0-9]*) sig=32 ;; esac
  if [ -x "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" ]; then
    "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" "$sig" "$cache_file" 2>/dev/null || true
  else
    rm -f "$cache_file" 2>/dev/null || true
    pkill -x -RTMIN+"$sig" waybar >/dev/null 2>&1 || true
  fi
}

case "${1:-}" in
  --next)
    idx=$(read_index)
    idx=$(((idx + 1) % mod_count))
    write_index "$idx"
    signal_refresh
    exit 0
    ;;
  --prev)
    idx=$(read_index)
    idx=$(((idx - 1 + mod_count) % mod_count))
    write_index "$idx"
    signal_refresh
    exit 0
    ;;
esac

gauges_enabled=$(waybar_settings_get '.visual.gauges.enabled' 'true')
gauge_width=$(waybar_settings_get '.visual.gauges.width' '8')
disk_path=$(waybar_settings_get '.disk.path' '/')

idx=$(read_index)
mod=$(printf '%s\n' "$modules" | sed -n "$((idx + 1))p")
[ -n "$mod" ] || mod=cpu

metrics="$("$WAYBAR_SCRIPTS/infra/system-metrics-collector.sh" 2>/dev/null || true)"

emit_cpu() {
  if [ -z "$metrics" ]; then
    emit_waybar_json "󰍛 --" "CPU telemetry unavailable" "disabled"
    return
  fi
  usage=$(printf '%s' "$metrics" | jq -r '.cpu.usage // 0')
  temp=$(printf '%s' "$metrics" | jq -r '.cpu.temp // 0')
  cpu_warn=$(waybar_settings_get '.thresholds.cpu.usage.warning' '60')
  cpu_crit=$(waybar_settings_get '.thresholds.cpu.usage.critical' '85')
  class="$(waybar_threshold_class "$usage" "$cpu_warn" "$cpu_crit")"
  text=$(printf '󰍛 %s' "$(gauge_or_pct "$usage")")
  tip=$(printf 'CPU %s%% · temp %s\nScroll: cycle stats (%s/%s)' "$usage" "$temp" "$((idx + 1))" "$mod_count")
  emit_waybar_json "$text" "$tip" "$class"
}

emit_memory() {
  if [ -z "$metrics" ]; then
    emit_waybar_json "󰘚 --" "Memory telemetry unavailable" "disabled"
    return
  fi
  pct=$(printf '%s' "$metrics" | jq -r '.memory.mem_pct // 0')
  used=$(printf '%s' "$metrics" | jq -r '.memory.mem_used_gib // "0"')
  total=$(printf '%s' "$metrics" | jq -r '.memory.mem_total_gib // "0"')
  mem_warn=$(waybar_settings_get '.thresholds.memory.warning' '70')
  mem_crit=$(waybar_settings_get '.thresholds.memory.critical' '85')
  class="$(waybar_threshold_class "$pct" "$mem_warn" "$mem_crit")"
  text=$(printf '󰘚 %s' "$(gauge_or_pct "$pct")")
  tip=$(printf 'Memory %s / %s GiB\nScroll: cycle stats (%s/%s)' "$used" "$total" "$((idx + 1))" "$mod_count")
  emit_waybar_json "$text" "$tip" "$class"
}

emit_disk() {
  df_info=$(df -h "$disk_path" 2>/dev/null | awk 'NR==2 {print $2, $3, $5}')
  set -- $df_info
  size="${1:-0}"
  used="${2:-0}"
  pct="${3:-0%}"
  percent_num=$(printf '%s' "$pct" | tr -d '%')
  disk_warn=$(waybar_settings_get '.thresholds.disk.warning' '75')
  disk_crit=$(waybar_settings_get '.thresholds.disk.critical' '90')
  class="$(waybar_threshold_class "$percent_num" "$disk_warn" "$disk_crit")"
  text=$(printf '󰋊 %s' "$(gauge_or_pct "$percent_num")")
  tip=$(printf 'Disk %s (%s used of %s)\nScroll: cycle stats (%s/%s)' "$disk_path" "$used" "$size" "$((idx + 1))" "$mod_count")
  emit_waybar_json "$text" "$tip" "$class"
}

emit_gpu() {
  if [ -z "$metrics" ]; then
    emit_waybar_json "󰢮 --" "GPU telemetry unavailable" "disabled"
    return
  fi
  avail=$(printf '%s' "$metrics" | jq -r '(.gpu.available // false) | tostring')
  if [ "$avail" != "true" ]; then
    emit_waybar_json "󰢮 --" "GPU telemetry unavailable" "disabled"
    return
  fi
  util=$(printf '%s' "$metrics" | jq -r '.gpu.util // 0')
  temp=$(printf '%s' "$metrics" | jq -r '.gpu.temp // 0')
  name=$(printf '%s' "$metrics" | jq -r '.gpu.name // "GPU"')
  gpu_warn=$(waybar_settings_get '.thresholds.gpu.util.warning' '70')
  gpu_crit=$(waybar_settings_get '.thresholds.gpu.util.critical' '90')
  class="$(waybar_threshold_class "$util" "$gpu_warn" "$gpu_crit")"
  text=$(printf '󰢮 %s' "$(gauge_or_pct "$util")")
  tip=$(printf '%s · %s%% · temp %s\nScroll: cycle stats (%s/%s)' "$name" "$util" "$temp" "$((idx + 1))" "$mod_count")
  emit_waybar_json "$text" "$tip" "$class"
}

case "$mod" in
  memory | mem) emit_memory ;;
  disk) emit_disk ;;
  gpu) emit_gpu ;;
  *) emit_cpu ;;
esac
