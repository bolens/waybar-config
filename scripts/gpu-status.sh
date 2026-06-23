#!/usr/bin/env sh
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
script_dir="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts"

. "$script_dir/waybar-cache-helpers.sh"
. "$script_dir/waybar-settings.sh"

gpu_warn=$(waybar_settings_get '.thresholds.gpu.util.warning' '70')
gpu_crit=$(waybar_settings_get '.thresholds.gpu.util.critical' '90')
gpu_temp_warn=$(waybar_settings_get '.thresholds.gpu.temp.warning' '75')
gpu_temp_crit=$(waybar_settings_get '.thresholds.gpu.temp.critical' '83')

cached_file="$cache_dir/gpu-icon.json"

# 1. Try to return the cached file immediately if it is fresh (<= 12 seconds)
if [ -f "$cached_file" ] && [ "$(cache_file_age "$cached_file")" -le 12 ] 2>/dev/null; then
  cat "$cached_file"
  exit 0
fi

# 2. If the file exists but is stale, output it immediately to avoid lag,
#    and trigger a background refresh of the metrics collector.
if [ -f "$cached_file" ]; then
  cat "$cached_file"
  # Avoid spawning multiple concurrent refreshes by checking lock_dir
  if [ ! -d "$cache_dir/system-metrics.lock.d" ]; then
    "$script_dir/system-metrics-collector.sh" --refresh >/dev/null 2>&1 &
  fi
  exit 0
fi

# 3. Hard fallback for the first launch if cache does not exist yet
metrics="$("$script_dir/system-metrics-collector.sh" 2>/dev/null || true)"
if [ -z "$metrics" ]; then
  jq -cn \
    --arg text "󰢮 --" \
    --arg tooltip "NVIDIA GPU telemetry unavailable" \
    --arg class "disabled" \
    '{text:$text, tooltip:$tooltip, class:$class}'
  exit 0
fi

gpu_fields="$(printf '%s\n' "$metrics" | jq -r '[
  ((.gpu.available // false) | tostring),
  (.gpu.name // "NVIDIA GPU"),
  (.gpu.util // 0),
  (.gpu.temp // 0),
  (.gpu.mem_used // 0),
  (.gpu.mem_total // 0),
  (.gpu.vram_pct // 0)
] | @tsv')"
tab=$(printf '\t')
old_ifs=$IFS
IFS=$tab
set -- $gpu_fields
IFS=$old_ifs

gpu_available="${1:-false}"
if [ "$gpu_available" != "true" ]; then
  jq -cn \
    --arg text "󰢮 --" \
    --arg tooltip "NVIDIA GPU telemetry unavailable" \
    --arg class "disabled" \
    '{text:$text, tooltip:$tooltip, class:$class}'
  exit 0
fi

name="${2:-NVIDIA GPU}"
util="${3:-0}"
temp="${4:-0}"
mem_used="${5:-0}"
mem_total="${6:-0}"
vram_pct="${7:-0}"

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

tooltip=$(printf '%s\nUtil: %s%%\nTemp: %s\nVRAM: %s/%s MiB (%s%%)' \
  "$name" "$util" "$formatted_temp" "$mem_used" "$mem_total" "$vram_pct")

jq -cn \
  --arg text "$(printf '󰢮 %3d%%' "$util")" \
  --arg tooltip "$tooltip" \
  --arg class "$class" \
  '{text:$text, tooltip:$tooltip, class:$class}'

