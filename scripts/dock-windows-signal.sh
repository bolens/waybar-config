#!/usr/bin/env sh
# Debounced Waybar refresh for the dock-windows module (RTMIN+11).
set -eu

script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck source=waybar-cache-helpers.sh
if [ -f "$script_dir/waybar-cache-helpers.sh" ]; then
  . "$script_dir/waybar-cache-helpers.sh"
else
  . "$HOME/.config/waybar/scripts/waybar-cache-helpers.sh"
fi
cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/dock-windows-status.json"
debounce_stamp="${XDG_RUNTIME_DIR:-/tmp}/waybar-dock-signal.stamp"
debounce_seconds="${WAYBAR_DOCK_SIGNAL_DEBOUNCE:-1}"

signal_dock_windows() {
  age=$(cache_file_age "$debounce_stamp")
  if [ "$age" -lt "$debounce_seconds" ] 2>/dev/null; then
    return 0
  fi
  mkdir -p "$(dirname "$debounce_stamp")"
  touch "$debounce_stamp" 2>/dev/null || true
  "$script_dir/waybar-signal.sh" 11 "$cache_file"
}

signal_focus_modules() {
  signal_dock_windows
  "$script_dir/waybar-signal.sh" 13
}
