#!/usr/bin/env bash
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
script_dir="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts"

. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/gauge-lib.sh"

cached_file="$cache_dir/memory-icon.json"

if serve_metrics_cache_or_refresh "$cached_file" 12 "$cache_dir" "$script_dir"; then
  exit 0
fi

# Thresholds only needed on cache miss / icon rebuild.
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
mem_warn=$(waybar_settings_get '.thresholds.memory.warning' '70')
mem_crit=$(waybar_settings_get '.thresholds.memory.critical' '85')
gauges_enabled=$(waybar_settings_get '.visual.gauges.enabled' 'true')
gauge_width=$(waybar_settings_get '.visual.gauges.width' '8')

# 3. Hard fallback for the first launch if cache does not exist yet
metrics="$("$WAYBAR_SCRIPTS/infra/system-metrics-collector.sh" 2>/dev/null || true)"
if [ -z "$metrics" ]; then
  emit_waybar_json "󰘚" "Memory telemetry unavailable" "disabled"
  exit 0
fi

mem_fields="$(printf '%s\n' "$metrics" | jq -r '[
  (.memory.mem_used_gib // "0.0"),
  (.memory.mem_total_gib // "0.0"),
  (.memory.mem_pct // 0),
  (.memory.swap_used_gib // "0.0"),
  (.memory.swap_total_gib // "0.0")
] | @tsv')"
tab=$(printf '\t')
old_ifs=$IFS
IFS=$tab
set -- $mem_fields
IFS=$old_ifs

mem_used_gib="${1:-0.0}"
mem_total_gib="${2:-0.0}"
mem_pct="${3:-0}"
swap_used_gib="${4:-0.0}"
swap_total_gib="${5:-0.0}"

tooltip=$(printf 'Memory: %s/%s GiB (%s%%)\nSwap: %s/%s GiB\n\nLeft: system monitor · Right: btop · Middle: Plasma system monitor' \
  "$mem_used_gib" "$mem_total_gib" "$mem_pct" "$swap_used_gib" "$swap_total_gib")

class="normal"
if [ "$mem_pct" -ge "$mem_crit" ] 2>/dev/null; then
  class="critical"
elif [ "$mem_pct" -ge "$mem_warn" ] 2>/dev/null; then
  class="warning"
fi

case "$gauges_enabled" in
  false | False | FALSE | 0 | no | No | NO | null | off | Off | OFF)
    text=$(printf '󰘚 %3d%%' "$mem_pct")
    ;;
  *)
    text=$(printf '󰘚 %s %3d%%' "$(gauge_bar "$mem_pct" "$gauge_width")" "$mem_pct")
    ;;
esac
emit_waybar_json "$text" "$tooltip" "$class"
