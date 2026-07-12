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

# Trigger an initial update via signals.device_notifier
"$WAYBAR_SCRIPTS/lib/waybar-signal.sh" device_notifier "$cache_file"

# Monitor block subsystem events and trigger updates
udevadm monitor --subsystem=block | while read -r line; do
  [ -n "$line" ] || continue
  "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" device_notifier "$cache_file"
done
