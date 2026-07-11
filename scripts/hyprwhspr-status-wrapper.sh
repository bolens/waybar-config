#!/usr/bin/env sh
set -eu

script_dir="${0%/*}"
. "$script_dir/waybar-cache-helpers.sh"
# shellcheck source=compositor-session.sh
. "$script_dir/compositor-session.sh"

if [ "$(detect_compositor)" != "hyprland" ]; then
  emit_waybar_json "" "" "hidden"
  exit 0
fi

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/hyprwhspr-status.json"
lock_dir="$cache_dir/hyprwhspr-status.lock.d"
ttl="$(waybar_module_interval hyprwhspr 30)"
stale_lock_ttl=45

mkdir -p "$cache_dir"


if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "" "Hyprwhspr status initializing" "disabled"
  exit 0
fi

json="$(timeout 3 /usr/lib/hyprwhspr/config/hyprland/hyprwhspr-tray.sh status 2>/dev/null || true)"
if [ -n "$json" ]; then
  tmp_cache="$cache_file.tmp.$$"
  printf '%s\n' "$json" > "$tmp_cache"
  mv -f "$tmp_cache" "$cache_file"
  printf '%s\n' "$json"
  exit 0
fi

emit_waybar_json "" "Hyprwhspr status unavailable" "disabled"
