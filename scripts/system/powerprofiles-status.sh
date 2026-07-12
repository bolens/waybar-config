#!/usr/bin/env sh
# Powerprofilesctl status for Waybar (hides when powerprofilesctl is absent).
set -eu

if ! command -v powerprofilesctl >/dev/null 2>&1; then
  jq -cn \
    --arg text "󰾅 --" \
    --arg tooltip "powerprofilesctl not installed" \
    --arg class "disabled" \
    '{text:$text, tooltip:$tooltip, class:$class}'
  exit 0
fi

current=$(powerprofilesctl get 2>/dev/null || true)
available=$(powerprofilesctl list 2>/dev/null || true)

if [ -z "$current" ]; then
  jq -cn \
    --arg text "󰾅 --" \
    --arg tooltip "Power profile daemon unavailable" \
    --arg class "critical" \
    '{text:$text, tooltip:$tooltip, class:$class}'
  exit 0
fi

class="$current"
icon="󰾆"

case "$current" in
  performance)
    icon="󱐋"
    ;;
  balanced)
    icon="󰾅"
    ;;
  power-saver)
    icon="󰓅"
    ;;
esac

tooltip=$(printf 'Current profile: %s' "$current")
if [ -n "$available" ]; then
  tooltip=$(printf '%s\n\nAvailable profiles:\n%s' "$tooltip" "$available")
fi

jq -cn \
  --arg text "$icon" \
  --arg tooltip "$tooltip" \
  --arg class "$class" \
  '{text:$text, tooltip:$tooltip, class:$class}'
