#!/usr/bin/env bash
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
script_dir="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts"

. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

cached_file="$cache_dir/gpu-icon.json"

if serve_metrics_cache_or_refresh "$cached_file" 12 "$cache_dir" "$script_dir"; then
  exit 0
fi

# Thresholds only needed on cache miss / icon rebuild.
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
gpu_warn=$(waybar_settings_get '.thresholds.gpu.util.warning' '70')
gpu_crit=$(waybar_settings_get '.thresholds.gpu.util.critical' '90')
gpu_temp_warn=$(waybar_settings_get '.thresholds.gpu.temp.warning' '75')
gpu_temp_crit=$(waybar_settings_get '.thresholds.gpu.temp.critical' '83')

# 3. Hard fallback for the first launch if cache does not exist yet
metrics="$("$WAYBAR_SCRIPTS/infra/system-metrics-collector.sh" 2>/dev/null || true)"
if [ -z "$metrics" ]; then
  emit_waybar_json "󰢮 --" "GPU telemetry unavailable" "disabled"
  exit 0
fi

gpu_fields="$(printf '%s\n' "$metrics" | jq -r '[
  ((.gpu.available // false) | tostring),
  (.gpu.name // "GPU"),
  (.gpu.util // 0),
  (.gpu.temp // 0),
  (.gpu.mem_used // 0),
  (.gpu.mem_total // 0),
  (.gpu.vram_pct // 0),
  (.gpu.vendor // "")
] | @tsv')"
tab=$(printf '\t')
old_ifs=$IFS
IFS=$tab
set -- $gpu_fields
IFS=$old_ifs

gpu_available="${1:-false}"
if [ "$gpu_available" != "true" ]; then
  emit_waybar_json "󰢮 --" "GPU telemetry unavailable" "disabled"
  exit 0
fi

name="${2:-GPU}"
util="${3:-0}"
temp="${4:-0}"
mem_used="${5:-0}"
mem_total="${6:-0}"
vram_pct="${7:-0}"
vendor="${8:-}"

formatted_temp="N/A"
if [ "$temp" -gt 0 ]; then
  formatted_temp=$(format_locale_temp "$temp")
fi

class="normal"
if [ "${temp:-0}" -ge "$gpu_temp_crit" ] 2>/dev/null || [ "${util:-0}" -ge "$gpu_crit" ] 2>/dev/null; then
  class="critical"
elif [ "${temp:-0}" -ge "$gpu_temp_warn" ] 2>/dev/null || [ "${util:-0}" -ge "$gpu_warn" ] 2>/dev/null; then
  class="warning"
fi

# AMD hwmon often lacks a true util % — show temp-forward text when util is a soft watt hint
if [ "$vendor" = "amd" ] && [ "${util:-0}" -lt 5 ] && [ "${temp:-0}" -gt 0 ]; then
  text=$(printf '󰢮 %s' "$formatted_temp")
else
  text=$(printf '󰢮 %3d%%' "$util")
fi

tooltip=$(printf '%s\nUtil: %s%%\nTemp: %s\nVRAM: %s/%s MiB (%s%%)' \
  "$name" "$util" "$formatted_temp" "$mem_used" "$mem_total" "$vram_pct")
[ -n "$vendor" ] && tooltip=$(printf '%s\nVendor: %s' "$tooltip" "$vendor")

emit_waybar_json "$text" "$tooltip" "$class"

