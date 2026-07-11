#!/usr/bin/env sh
# side-info-system-summary.sh: system summary logic for side-info-status.sh

: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
script_dir="$(dirname "$0")"
. "$WAYBAR_SCRIPTS/lib/side-info-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

system_summary() {
  cache_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-side-graphs/cache"
  mkdir -p "$cache_dir"
  if command -v read_cached_summary >/dev/null 2>&1; then
    cached="$(read_cached_summary "$cache_dir" system 2>/dev/null || true)"
    if [ -n "$cached" ]; then
      printf '%s\n' "$cached"
      return
    fi
  fi

  metrics="$($WAYBAR_SCRIPTS/infra/system-metrics-collector.sh 2>/dev/null || true)"

  cpu_usage='0'
  load_1='0.00'
  load_5='0.00'
  load_15='0.00'
  mem_used_gib='0.0'
  mem_total_gib='0.0'
  mem_pct='0'
  swap_used_gib='0.0'
  swap_total_gib='0.0'
  gpu_tooltip=''
  gpu_util=''
  gpu_temp=''

  if [ -n "$metrics" ]; then
    metrics_fields="$(printf '%s\n' "$metrics" | jq -r '[
      (.cpu.usage // 0),
      (.cpu.load.one // "0.00"),
      (.cpu.load.five // "0.00"),
      (.cpu.load.fifteen // "0.00"),
      (.memory.mem_used_gib // "0.0"),
      (.memory.mem_total_gib // "0.0"),
      (.memory.mem_pct // 0),
      (.memory.swap_used_gib // "0.0"),
      (.memory.swap_total_gib // "0.0"),
      ((.gpu.available // false) | tostring),
      (.gpu.name // "NVIDIA GPU"),
      (.gpu.util // 0),
      (.gpu.temp // 0),
      (.gpu.mem_used // 0),
      (.gpu.mem_total // 0),
      (.gpu.vram_pct // 0)
    ] | @tsv')"
    tab="$(printf '\t')"
    old_ifs=$IFS
    IFS=$tab
    set -- $metrics_fields
    IFS=$old_ifs

    cpu_usage="${1:-0}"
    load_1="${2:-0.00}"
    load_5="${3:-0.00}"
    load_15="${4:-0.00}"
    mem_used_gib="${5:-0.0}"
    mem_total_gib="${6:-0.0}"
    mem_pct="${7:-0}"
    swap_used_gib="${8:-0.0}"
    swap_total_gib="${9:-0.0}"
    gpu_available="${10:-false}"

    if [ "$gpu_available" = "true" ]; then
      gpu_name="${11:-NVIDIA GPU}"
      gpu_util_raw="${12:-0}"
      gpu_temp_raw="${13:-0}"
      gpu_mem_used="${14:-0}"
      gpu_mem_total="${15:-0}"
      gpu_vram_pct="${16:-0}"
      gpu_util="${gpu_util_raw}%"
      
      gpu_temp="N/A"
      gpu_temp_formatted="N/A"
      if [ "$gpu_temp_raw" -gt 0 ]; then
        gpu_temp=$(format_locale_temp "$gpu_temp_raw" "short")
        gpu_temp_formatted=$(format_locale_temp "$gpu_temp_raw" "both")
      fi
      gpu_tooltip="$(printf '%s\nUtil: %s%%\nTemp: %s\nVRAM: %s/%s MiB (%s%%)' "$gpu_name" "$gpu_util_raw" "$gpu_temp_formatted" "$gpu_mem_used" "$gpu_mem_total" "$gpu_vram_pct")"
    fi
  fi

  uptime_seconds="$(awk '{print int($1)}' /proc/uptime 2>/dev/null || printf '0')"
  uptime_text="$(format_duration_short "$uptime_seconds")"

  root_df="$(df -hP / 2>/dev/null | awk 'NR==2 {print $3, $2, $4, $5}')"
  set -- $root_df
  root_used="${1:-n/a}"
  root_total="${2:-n/a}"
  root_free="${3:-n/a}"
  root_pct="${4:-n/a}"

  waybar_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
  ups_json=""
  for ups_cache in \
    "$waybar_cache_dir/ups-status.ups_127.0.0.1_3493.json" \
    "$waybar_cache_dir/ups-status.auto.json"
  do
    ups_json="$(read_fresh_cache_file "$ups_cache" 30 2>/dev/null || true)"
    [ -n "$ups_json" ] && break
  done
  if [ -z "$ups_json" ]; then
    ups_json="$($WAYBAR_SCRIPTS/system/ups-status.sh 2>/dev/null || true)"
  fi
  ups_tooltip=''
  ups_charge=''
  if [ -n "$ups_json" ]; then
    {
      read -r ups_charge
      ups_tooltip=$(cat)
    } <<EOF
$(printf '%s\n' "$ups_json" | jq -r '((if (.text | test("[0-9]+%")) then (.text | match("[0-9]+%") | .string) else "" end) // ""), (.tooltip // "")')
EOF
    [ "$ups_charge" = "?" ] && ups_charge=''
  fi

  night_json="$($WAYBAR_SCRIPTS/services/desktop/nightlight-status.sh 2>/dev/null || true)"
  night_tooltip=''
  night_value=''
  if [ -n "$night_json" ]; then
    {
      read -r night_value
      night_tooltip=$(cat)
    } <<EOF
$(printf '%s\n' "$night_json" | jq -r '((.text | split(" ") | .[1]) // ""), (.tooltip // "")')
EOF
  fi

  summary="$(jq -cn \
    --arg line1 "$(format_lr "Uptime" "$uptime_text")" \
    --arg line2 "$(format_lr "CPU usage" "${cpu_usage}%")" \
    --arg line3 "$(format_lr "Load 1m" "$load_1")" \
    --arg line4 "$(format_lr "Memory" "${mem_used_gib}/${mem_total_gib}G")" \
    --arg line5 "$(format_lr "Swap" "${swap_used_gib}/${swap_total_gib}G")" \
    --arg line6 "$(format_lr "Root used" "${root_used}/${root_total}")" \
    --arg line7 "$(format_lr "GPU util" "$(item_text_or_dash "$gpu_util")")" \
    --arg line8 "$(format_lr "GPU temp" "$(item_text_or_dash "$gpu_temp")")" \
    --arg line9 "$(format_lr "UPS" "$(item_text_or_dash "$ups_charge")")" \
    --arg line10 "$(format_lr "Night light" "$(item_text_or_dash "$night_value")")" \
    --arg tooltip "System telemetry overview" \
    --arg tooltip1 "System uptime: ${uptime_text} (${uptime_seconds}s since boot)" \
    --arg tooltip2 "CPU usage: ${cpu_usage}%. Load averages: ${load_1} / ${load_5} / ${load_15}." \
    --arg tooltip3 "Load averages 1m/5m/15m: ${load_1} / ${load_5} / ${load_15}." \
    --arg tooltip4 "Memory used: ${mem_used_gib}/${mem_total_gib} GiB (${mem_pct}%)." \
    --arg tooltip5 "Swap used: ${swap_used_gib}/${swap_total_gib} GiB." \
    --arg tooltip6 "Root filesystem: used ${root_used} of ${root_total}, free ${root_free}, utilization ${root_pct}." \
    --arg tooltip7 "$(item_text_or_dash "$gpu_tooltip")" \
    --arg tooltip8 "$(item_text_or_dash "$gpu_tooltip")" \
    --arg tooltip9 "$(item_text_or_dash "$ups_tooltip")" \
    --arg tooltip10 "$(item_text_or_dash "$night_tooltip")" \
    --arg class "normal" \
    '{line1:$line1, line2:$line2, line3:$line3, line4:$line4, line5:$line5, line6:$line6, line7:$line7, line8:$line8, line9:$line9, line10:$line10, tooltip:$tooltip, tooltip1:$tooltip1, tooltip2:$tooltip2, tooltip3:$tooltip3, tooltip4:$tooltip4, tooltip5:$tooltip5, tooltip6:$tooltip6, tooltip7:$tooltip7, tooltip8:$tooltip8, tooltip9:$tooltip9, tooltip10:$tooltip10, class:$class}')"

  if command -v write_cached_summary >/dev/null 2>&1; then
    write_cached_summary "$cache_dir" system "$summary"
  fi

  printf '%s\n' "$summary"
}
