#!/usr/bin/env bash
# KDE Klipper clipboard status for Waybar (one-shot; listener keeps cache warm).
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

script_dir="${0%/*}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/clipboard-status.json"
cache_ttl="$(waybar_module_interval clipboard 120)"

# shellcheck source=clipboard-lib.sh
. "$WAYBAR_SCRIPTS/lib/clipboard-lib.sh"

if cached="$(read_fresh_cache_file "$cache_file" "$cache_ttl" 2>/dev/null || true)" && [ -n "$cached" ]; then
  printf '%s\n' "$cached"
  exit 0
fi

if ! kde_klipper_available; then
  printf '{"text":"󰅌","class":"unknown","alt":"unknown","tooltip":"Klipper is not available"}\n'
  exit 0
fi

count="$(kde_clipboard_count)"
latest="$(kde_clipboard_latest)"
print_clipboard_status "$count" "$latest" "Klipper"
