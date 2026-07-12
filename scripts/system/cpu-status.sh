#!/usr/bin/env bash
# CPU usage / temp icon module — serves metrics-icons cache or rebuilds on miss.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
script_dir="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts"

. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-locale-lib.sh"
. "$WAYBAR_SCRIPTS/lib/gauge-lib.sh"

cached_file="$cache_dir/cpu-icon.json"

if serve_metrics_cache_or_refresh "$cached_file" 8 "$cache_dir" "$script_dir"; then
  exit 0
fi

# Thresholds only needed on cache miss / icon rebuild.
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
cpu_warn=$(waybar_settings_get '.thresholds.cpu.usage.warning' '60')
cpu_crit=$(waybar_settings_get '.thresholds.cpu.usage.critical' '85')
cpu_temp_warn=$(waybar_settings_get '.thresholds.cpu.temp.warning' '75')
cpu_temp_crit=$(waybar_settings_get '.thresholds.cpu.temp.critical' '85')
gauges_enabled=$(waybar_settings_get '.visual.gauges.enabled' 'true')
gauge_width=$(waybar_settings_get '.visual.gauges.width' '8')

# First-launch fallback when the collector has not written a cache yet.
metrics="$("$WAYBAR_SCRIPTS/infra/system-metrics-collector.sh" 2>/dev/null || true)"
if [ -z "$metrics" ]; then
  emit_waybar_json "󰍛" "CPU telemetry unavailable" "disabled"
  exit 0
fi

cpu_fields="$(printf '%s\n' "$metrics" | jq -r '[
  (.cpu.usage // 0),
  (.cpu.topology.cores // 0),
  (.cpu.topology.threads // 0),
  (.cpu.topology.threads_per_core // 1),
  (.cpu.load.one // "0.00"),
  (.cpu.load.five // "0.00"),
  (.cpu.load.fifteen // "0.00"),
  (.cpu.load.runnable // "0/0"),
  (.cpu.load.pct.one // 0),
  (.cpu.load.pct.five // 0),
  (.cpu.load.pct.fifteen // 0),
  (.cpu.temp // 0)
] | @tsv')"
tab=$(printf '\t')
old_ifs=$IFS
IFS=$tab
set -- $cpu_fields
IFS=$old_ifs

usage="${1:-0}"
cores="${2:-0}"
threads="${3:-0}"
threads_per_core="${4:-1}"
load_1="${5:-0.00}"
load_5="${6:-0.00}"
load_15="${7:-0.00}"
runnable="${8:-0/0}"
load_pct_1="${9:-0}"
load_pct_5="${10:-0}"
load_pct_15="${11:-0}"
temp="${12:-0}"

formatted_temp="N/A"
if [ "$temp" -gt 0 ]; then
  formatted_temp=$(format_locale_temp "$temp")
fi

tooltip=$(printf 'CPU Utilization: %s%%\nTopology: %s cores / %s threads (%sT per core)\nLoad 1m/5m/15m: %s / %s / %s\nLoad vs thread capacity: %s%% / %s%% / %s%%\nRunnable tasks: %s\nTemperature: %s\n\nLeft: system monitor · Right: btop · Middle: Plasma system monitor' \
  "$usage" "$cores" "$threads" "$threads_per_core" "$load_1" "$load_5" "$load_15" "$load_pct_1" "$load_pct_5" "$load_pct_15" "$runnable" "$formatted_temp")

class="$(waybar_threshold_class "$usage" "$cpu_warn" "$cpu_crit" "$temp" "$cpu_temp_warn" "$cpu_temp_crit")"

text="$(gauge_status_text "󰍛" "$usage")"
emit_waybar_json "$text" "$tooltip" "$class"
