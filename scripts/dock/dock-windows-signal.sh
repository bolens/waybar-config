#!/usr/bin/env sh
# Debounced Waybar refresh for the dock-windows module.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

# shellcheck source=waybar-cache-helpers.sh
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/dock-windows-status.json"
debounce_stamp="${XDG_RUNTIME_DIR:-/tmp}/waybar-dock-signal.stamp"
debounce_seconds="${WAYBAR_DOCK_SIGNAL_DEBOUNCE:-1}"
settings="$WAYBAR_HOME/data/waybar-settings.json"
dock_sig=11
if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
  dock_sig="$(jq -r '.signals.dock_windows // 11' "$settings")"
fi

age=$(cache_file_age "$debounce_stamp")
if [ "$age" -lt "$debounce_seconds" ] 2>/dev/null; then
  exit 0
fi
mkdir -p "$(dirname "$debounce_stamp")"
touch "$debounce_stamp" 2>/dev/null || true
"$WAYBAR_SCRIPTS/lib/waybar-signal.sh" "$dock_sig" "$cache_file"
