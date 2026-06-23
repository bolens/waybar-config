#!/usr/bin/env sh
set -eu

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
. "$script_dir/compositor-session.sh"

if [ "$(detect_compositor)" != "hyprland" ]; then
  jq -cn '{text:"",class:"hidden",tooltip:""}'
  exit 0
fi

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
. "$script_dir/waybar-cache-helpers.sh"
cache_file="$cache_dir/hyprwhspr-status.json"
lock_dir="$cache_dir/hyprwhspr-status.lock.d"
ttl=30
stale_lock_ttl=45

mkdir -p "$cache_dir"


if [ "${1:-}" != "--refresh" ]; then
  age=$(cache_file_age "$cache_file")
  if [ "$age" -le "$ttl" ] 2>/dev/null; then
    cat "$cache_file"
    exit 0
  fi

  cleanup_stale_lock_dir "$lock_dir" "$stale_lock_ttl"

  if [ -f "$cache_file" ]; then
    [ -d "$lock_dir" ] || refresh_in_background
    cat "$cache_file"
    exit 0
  fi

  [ -d "$lock_dir" ] || refresh_in_background
  jq -cn --arg text "" --arg class "disabled" --arg tooltip "Hyprwhspr status initializing" '{text:$text,class:$class,tooltip:$tooltip}'
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

jq -cn --arg text "" --arg class "disabled" --arg tooltip "Hyprwhspr status unavailable" '{text:$text,class:$class,tooltip:$tooltip}'
