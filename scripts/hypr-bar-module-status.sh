#!/usr/bin/env sh
# Hide Hyprland-only bar modules when not running Hyprland (hyprwhspr stays visible on KDE).
set -eu

module="${1:-}"
script_dir="${0%/*}"
. "$script_dir/compositor-session.sh"

hidden_json() {
  jq -cn '{text:"", tooltip:"", class:"hidden"}'
}

compositor="$(detect_compositor)"

if [ "$compositor" != "hyprland" ]; then
  hidden_json
  exit 0
fi

case "$module" in
  notify)
    jq -cn '{text:"󰂚", tooltip:"Show notifications", class:"ready"}'
    ;;
  light)
    jq -cn '{text:"󰃠", tooltip:"Adjust brightness", class:"ready"}'
    ;;
  *)
    hidden_json
    ;;
esac
