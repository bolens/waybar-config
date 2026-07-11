#!/usr/bin/env sh
# Brightness status for Waybar (one-shot; listener keeps cache warm on KDE).
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

script_dir="${0%/*}"
cache_ttl="$(waybar_module_interval brightness 120)"

# shellcheck source=waybar-cache-helpers.sh
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
# shellcheck source=brightness-lib.sh
. "$WAYBAR_SCRIPTS/lib/brightness-lib.sh"

case "${1:-}" in
  --refresh)
    output=$(brightness_collect_status_json "$script_dir")
    brightness_write_cache "$output"
    printf '%s\n' "$output"
    ;;
  *)
    if cached="$(read_fresh_cache_file "$brightness_cache_file" "$cache_ttl" 2>/dev/null || true)" && [ -n "$cached" ]; then
      printf '%s\n' "$cached"
      exit 0
    fi

    if [ -f "$brightness_cache_file" ]; then
      cat "$brightness_cache_file"
      exit 0
    fi

    output=$(brightness_collect_status_json "$script_dir")
    brightness_write_cache "$output"
    printf '%s\n' "$output"
    ;;
esac
