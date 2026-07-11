#!/usr/bin/env bash
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/libredefender-status.json"
lock_dir="$cache_dir/libredefender-status.lock.d"
ttl="$(waybar_module_interval libredefender 15)"
stale_lock_ttl=20

mkdir -p "$cache_dir"

script_dir="${0%/*}"
# Handle sourcing when run directly or by Waybar
if [ -f "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh" ]; then
  . "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
else
  . "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
fi
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
service_name=$(waybar_settings_get '.services.libredefender.service_name' 'libredefender-scan.service')

check_systemd_scan_service \
  "$service_name" \
  "libredefender-scan" \
  "LibreDefender Antivirus" \
  "Libre" \
  "󰒃" \
  "$cache_file" \
  "$lock_dir" \
  "$ttl" \
  "$stale_lock_ttl" \
  "604800" \
  "Scan Stale (> 7 days)" \
  "Left: start weekly scan · Right: view service logs · Middle: refresh" \
  "$0" \
  "${1:-}"
