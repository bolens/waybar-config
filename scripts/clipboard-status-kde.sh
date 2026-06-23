#!/usr/bin/env sh
# KDE Klipper clipboard status for Waybar (one-shot; listener keeps cache warm).
set -eu

script_dir="${0%/*}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/clipboard-status.json"
cache_ttl=120

# shellcheck source=waybar-cache-helpers.sh
. "$script_dir/waybar-cache-helpers.sh"
# shellcheck source=clipboard-lib.sh
. "$script_dir/clipboard-lib.sh"

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
