#!/usr/bin/env sh
# side-info-cache.sh: Caching and request helpers for side-info-status.sh
# TTL values mirror config.jsonc module intervals (see waybar-poll-ttl.sh).

if [ -z "${script_dir:-}" ]; then
  script_dir="$(dirname "$0")"
fi
# shellcheck source=waybar-cache-helpers.sh
if [ -f "$script_dir/waybar-cache-helpers.sh" ]; then
  . "$script_dir/waybar-cache-helpers.sh"
else
  . "$HOME/.config/waybar/scripts/waybar-cache-helpers.sh"
fi

cache_file_for() {
  cache_dir="$1"
  tab="$2"
  printf '%s/%s-summary.json' "$cache_dir" "$tab"
}

cache_ttl_for() {
  tab="$1"
  case "$tab" in
    docker) printf '30' ;;
    updates) printf '300' ;;
    stats) printf '8' ;;
    network) printf '15' ;;
    system) printf '15' ;;
    runtimes) printf '600' ;;
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
