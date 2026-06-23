#!/usr/bin/env sh
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
script_dir="$HOME/.config/waybar/scripts"

. "$script_dir/waybar-cache-helpers.sh"

cached_file="$cache_dir/memory-icon.json"

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
    --arg text "󰘚" \
    --arg tooltip "Memory telemetry unavailable" \
    --arg class "disabled" \
    '{text:$text, tooltip:$tooltip, class:$class}'
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

tooltip=$(printf 'Memory: %s/%s GiB (%s%%)\nSwap: %s/%s GiB' \
  "$mem_used_gib" "$mem_total_gib" "$mem_pct" "$swap_used_gib" "$swap_total_gib")

class="normal"
if [ "$mem_pct" -ge 85 ] 2>/dev/null; then
  class="critical"
elif [ "$mem_pct" -ge 70 ] 2>/dev/null; then
  class="warning"
fi

jq -cn \
  --arg text "$(printf '󰘚 %3d%%' "$mem_pct")" \
  --arg tooltip "$tooltip" \
  --arg class "$class" \
  '{text:$text, tooltip:$tooltip, class:$class}'

