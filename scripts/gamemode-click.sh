#!/usr/bin/env sh
set -eu

script_dir="${0%/*}"
action="${1:-toggle}"

# shellcheck source=compositor-session.sh
. "$script_dir/compositor-session.sh"

[ "$(detect_compositor)" = "hyprland" ] || exit 0
command -v hyprctl >/dev/null 2>&1 || exit 0

case "$action" in
  toggle)
    enabled="$(hyprctl getoption animations:enabled 2>/dev/null | awk '/int/ {print $2}')"
    if [ "$enabled" = "0" ]; then
      hyprctl reload >/dev/null 2>&1 || true
    else
      hyprctl --batch "
        keyword animations:enabled 0;
        keyword decoration:blur:enabled 0;
        keyword decoration:shadow:enabled 0
      " >/dev/null 2>&1 || true
    fi
    ;;
  restore)
    hyprctl reload >/dev/null 2>&1 || true
    ;;
  *)
    printf 'Usage: %s [toggle|restore]\n' "$0" >&2
    exit 1
    ;;
esac

pkill -x -RTMIN+15 waybar >/dev/null 2>&1 || true
