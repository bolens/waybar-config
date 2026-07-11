#!/usr/bin/env sh
# side-info-cache.sh: Caching and request helpers for side-info-status.sh
# TTL values mirror config.jsonc module intervals (see waybar-poll-ttl.sh).

: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
if [ -z "${script_dir:-}" ]; then
  script_dir="$(dirname "$0")"
fi
# shellcheck source=waybar-cache-helpers.sh
if [ -f "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh" ]; then
  . "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
else
  . "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
fi

cache_file_for() {
  cache_dir="$1"
  tab="$2"
  printf '%s/%s-summary.json' "$cache_dir" "$tab"
}

cache_ttl_for() {
  tab="$1"
  case "$tab" in
    docker) waybar_module_interval docker 30 ;;
    updates) waybar_module_interval updates_tab 300 ;;
    stats) waybar_module_interval cpu 8 ;;
    network) waybar_module_interval network_tab 15 ;;
    system) waybar_module_interval system_tab 15 ;;
    runtimes) waybar_module_interval runtimes 600 ;;
    *) printf '0' ;;
  esac
}

read_cached_summary() {
  cache_dir="$1"
  tab="$2"
  file="$(cache_file_for "$cache_dir" "$tab")"
  ttl="$(cache_ttl_for "$tab")"
  read_fresh_cache_file "$file" "$ttl" 2>/dev/null
}

write_cached_summary() {
  cache_dir="$1"
  tab="$2"
  summary="$3"
  file="$(cache_file_for "$cache_dir" "$tab")"
  tmp="$file.tmp.$$"
  printf '%s\n' "$summary" > "$tmp"
  mv -f "$tmp" "$file"
}
