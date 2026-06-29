#!/usr/bin/env sh
# Listen for block device changes via udev and trigger Waybar signals.
set -eu

script_dir="${0%/*}"

cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/device-notifier-status.json"

# Trigger an initial update signal
"$script_dir/waybar-signal.sh" 19 "$cache_file"

# Monitor block subsystem events and trigger updates
udevadm monitor --subsystem=block | while read -r line; do
  # Skip lines that are empty
  [ -n "$line" ] || continue
  # Trigger signal 19
  "$script_dir/waybar-signal.sh" 19 "$cache_file"
done
