#!/usr/bin/env bash
# Rotate cpu/memory/disk/gpu into one Waybar module; scroll cycles the active metric.
# Cache/serve pattern matches disk-status; gauges/tooltips match cpu/memory peers.
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
lock_dir="$cache_dir/stats-carousel.lock.d"
ttl="$(waybar_module_interval stats_carousel 8)"
stale_lock_ttl=15

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

# Signal Waybar without deleting cache (caller just wrote fresh JSON).
signal_bar() {
  if [ -x "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" ]; then
    "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" stats_carousel 2>/dev/null || true
  else
    sig=$(waybar_settings_get '.signals.stats_carousel' '32')
    pkill -x -RTMIN+"$sig" waybar >/dev/null 2>&1 || true
  fi
}

click_hints() {
  printf 'Scroll: cycle stats (%s/%s)\nLeft: system monitor · Right: btop · Middle: refresh' \
    "$((idx + 1))" "$mod_count"
}

emit_and_cache() {
  gauges_enabled=$(waybar_settings_get '.visual.gauges.enabled' 'true')
  gauge_width=$(waybar_settings_get '.visual.gauges.width' '8')
  disk_path=$(waybar_settings_get '.disk.path' '/')

  idx=$(read_index)
  mod=$(printf '%s\n' "$modules" | sed -n "$((idx + 1))p")
  [ -n "$mod" ] || mod=cpu

  metrics="$("$WAYBAR_SCRIPTS/infra/system-metrics-collector.sh" 2>/dev/null || true)"
  hints=$(click_hints)
  json=""

  case "$mod" in
    memory | mem)
      if [ -z "$metrics" ]; then
        json=$(emit_waybar_json "󰘚 --" "Memory telemetry unavailable" "disabled")
      else
        pct=$(printf '%s' "$metrics" | jq -r '.memory.mem_pct // 0')
        used=$(printf '%s' "$metrics" | jq -r '.memory.mem_used_gib // "0"')
        total=$(printf '%s' "$metrics" | jq -r '.memory.mem_total_gib // "0"')
        mem_warn=$(waybar_settings_get '.thresholds.memory.warning' '70')
        mem_crit=$(waybar_settings_get '.thresholds.memory.critical' '85')
        class="$(waybar_threshold_class "$pct" "$mem_warn" "$mem_crit")"
        text=$(gauge_status_text "󰘚" "$pct")
        tip=$(printf 'Memory: %s/%s GiB (%s%%)\n%s' "$used" "$total" "$pct" "$hints")
        json=$(emit_waybar_json "$text" "$tip" "$class")
      fi
      ;;
    disk)
      df_info=$(df -h "$disk_path" 2>/dev/null | awk 'NR==2 {print $2, $3, $4, $5}')
      set -- $df_info
      size="${1:-0}"
      used="${2:-0}"
      avail="${3:-0}"
      pct="${4:-0%}"
      percent_num=$(printf '%s' "$pct" | tr -d '%')
      disk_warn=$(waybar_settings_get '.thresholds.disk.warning' '75')
      disk_crit=$(waybar_settings_get '.thresholds.disk.critical' '90')
      class="$(waybar_threshold_class "$percent_num" "$disk_warn" "$disk_crit")"
      text=$(gauge_status_text "󰋊" "$percent_num")
      tip=$(printf 'Disk Space (%s)\nTotal: %s\nUsed: %s\nAvailable: %s\nUsage: %s\n%s' \
        "$disk_path" "$size" "$used" "$avail" "$pct" "$hints")
      json=$(emit_waybar_json "$text" "$tip" "$class")
      ;;
    gpu)
      if [ -z "$metrics" ]; then
        json=$(emit_waybar_json "󰢮 --" "GPU telemetry unavailable" "disabled")
      else
        avail=$(printf '%s' "$metrics" | jq -r '(.gpu.available // false) | tostring')
        if [ "$avail" != "true" ]; then
          json=$(emit_waybar_json "󰢮 --" "GPU telemetry unavailable" "disabled")
        else
          util=$(printf '%s' "$metrics" | jq -r '.gpu.util // 0')
          temp=$(printf '%s' "$metrics" | jq -r '.gpu.temp // 0')
          name=$(printf '%s' "$metrics" | jq -r '.gpu.name // "GPU"')
          gpu_warn=$(waybar_settings_get '.thresholds.gpu.util.warning' '70')
          gpu_crit=$(waybar_settings_get '.thresholds.gpu.util.critical' '90')
          gpu_temp_warn=$(waybar_settings_get '.thresholds.gpu.temp.warning' '75')
          gpu_temp_crit=$(waybar_settings_get '.thresholds.gpu.temp.critical' '90')
          class="$(waybar_threshold_class "$util" "$gpu_warn" "$gpu_crit" "$temp" "$gpu_temp_warn" "$gpu_temp_crit")"
          text=$(gauge_status_text "󰢮" "$util")
          formatted_temp="N/A"
          if [ "$temp" -gt 0 ] 2>/dev/null; then
            formatted_temp=$(format_locale_temp "$temp")
          fi
          tip=$(printf '%s · %s%% · temp %s\n%s' "$name" "$util" "$formatted_temp" "$hints")
          json=$(emit_waybar_json "$text" "$tip" "$class")
        fi
      fi
      ;;
    *)
      if [ -z "$metrics" ]; then
        json=$(emit_waybar_json "󰍛 --" "CPU telemetry unavailable" "disabled")
      else
        usage=$(printf '%s' "$metrics" | jq -r '.cpu.usage // 0')
        temp=$(printf '%s' "$metrics" | jq -r '.cpu.temp // 0')
        cpu_warn=$(waybar_settings_get '.thresholds.cpu.usage.warning' '60')
        cpu_crit=$(waybar_settings_get '.thresholds.cpu.usage.critical' '85')
        cpu_temp_warn=$(waybar_settings_get '.thresholds.cpu.temp.warning' '75')
        cpu_temp_crit=$(waybar_settings_get '.thresholds.cpu.temp.critical' '85')
        class="$(waybar_threshold_class "$usage" "$cpu_warn" "$cpu_crit" "$temp" "$cpu_temp_warn" "$cpu_temp_crit")"
        text=$(gauge_status_text "󰍛" "$usage")
        formatted_temp="N/A"
        if [ "$temp" -gt 0 ] 2>/dev/null; then
          formatted_temp=$(format_locale_temp "$temp")
        fi
        tip=$(printf 'CPU Utilization: %s%%\nTemperature: %s\n%s' "$usage" "$formatted_temp" "$hints")
        json=$(emit_waybar_json "$text" "$tip" "$class")
      fi
      ;;
  esac

  printf '%s\n' "$json"
  tmp_cache="$cache_file.tmp.$$"
  printf '%s\n' "$json" >"$tmp_cache"
  mv -f "$tmp_cache" "$cache_file"
}

case "${1:-}" in
  --next)
    idx=$(read_index)
    idx=$(((idx + 1) % mod_count))
    write_index "$idx"
    emit_and_cache >/dev/null
    signal_bar
    exit 0
    ;;
  --prev)
    idx=$(read_index)
    idx=$(((idx - 1 + mod_count) % mod_count))
    write_index "$idx"
    emit_and_cache >/dev/null
    signal_bar
    exit 0
    ;;
  --refresh)
    emit_and_cache
    # Middle-click: push bar without wiping the cache we just wrote.
    # Background refresh (WAYBAR_BACKGROUND=1) must not signal — that would loop.
    if [ "${WAYBAR_BACKGROUND:-}" != "1" ]; then
      signal_bar
    fi
    exit 0
    ;;
esac

# Poll path (Waybar interval): serve cache or kick background --refresh.
if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
  exit 0
fi
emit_waybar_json "󰍛 --" "Initializing stats carousel..." "normal"
exit 0
