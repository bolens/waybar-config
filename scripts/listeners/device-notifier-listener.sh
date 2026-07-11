#!/usr/bin/env sh
# Listen for block device changes via udev and trigger Waybar signals.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
# shellcheck source=dock-windows-listener-lock.sh
WAYBAR_LISTENER_LOCK_NAME=device-notifier
. "$script_dir/dock-windows-listener-lock.sh"

cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/device-notifier-status.json"
WAYBAR_HOME="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
settings="$WAYBAR_HOME/data/waybar-settings.json"
sig=19
if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
  sig="$(jq -r '.signals.device_notifier // 19' "$settings")"
fi

# Trigger an initial update signal
"$WAYBAR_SCRIPTS/lib/waybar-signal.sh" "$sig" "$cache_file"

# Monitor block subsystem events and trigger updates
udevadm monitor --subsystem=block | while read -r line; do
  [ -n "$line" ] || continue
  "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" "$sig" "$cache_file"
done
