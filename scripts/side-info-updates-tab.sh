
#!/usr/bin/env sh
# Standalone updates tab script for Waybar custom module (now uses updates-status.sh cache)
set -eu
trap '' PIPE

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
. "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-cache-helpers.sh"
cache_file="$cache_dir/updates-status.json"

# TTL matches updates-status.sh / bottom-bar custom/updates interval (300s).
ttl=300

if [ -f "$cache_file" ]; then
  age=$(cache_file_age "$cache_file")
  if [ "$age" -le "$ttl" ] 2>/dev/null; then
    cat "$cache_file"
    exit 0
  fi
fi

# If cache is missing or stale, trigger background refresh (non-blocking)
(${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/updates-status.sh >/dev/null 2>&1 &) || true

# Show placeholder if no cache, else show stale cache
if [ -f "$cache_file" ]; then
  cat "$cache_file"
else
  jq -cn --arg msg "Updates cache warming; check again shortly" '{"tooltip":$msg,"class":"disabled"}'
fi
