#!/usr/bin/env bash
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/chkrootkit-status.json"
lock_dir="$cache_dir/chkrootkit-status.lock.d"
ttl="$(waybar_module_interval chkrootkit 15)"
stale_lock_ttl=20

mkdir -p "$cache_dir"

. "$WAYBAR_SCRIPTS/lib/waybar-locale-lib.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-systemd-scan-lib.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
service_name=$(waybar_settings_get '.services.chkrootkit.service_name' 'chkrootkit-scan.service')

check_systemd_scan_service \
  "$service_name" \
  "chkrootkit-scan" \
  "chkrootkit Rootkit Scanner" \
  "Chkroot" \
  "󰖳" \
  "$cache_file" \
  "$lock_dir" \
  "$ttl" \
  "$stale_lock_ttl" \
  "86400" \
  "Scan Stale (> 24 hours)" \
  "Left: start daily scan · Right: view service logs · Middle: refresh" \
  "$0" \
  "${1:-}"
