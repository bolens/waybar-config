#!/usr/bin/env bash
# Screen recorder status for Waybar (one-shot; listener keeps cache warm).
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

script_dir="${0%/*}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/screenrecord-status.json"
cache_ttl="$(waybar_module_interval screenrecord 120)"

# shellcheck source=waybar-cache-helpers.sh
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
# shellcheck source=capture-lib.sh
. "$WAYBAR_SCRIPTS/lib/capture-lib.sh"

if cached="$(read_fresh_cache_file "$cache_file" "$cache_ttl" 2>/dev/null || true)" && [ -n "$cached" ]; then
  printf '%s\n' "$cached"
  exit 0
fi

compositor="$(detect_compositor)"
capture_emit_screenrecord_status "$compositor"
