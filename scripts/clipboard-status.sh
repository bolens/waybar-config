#!/usr/bin/env sh
# Route clipboard status to the active compositor backend.
set -eu

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
. "$script_dir/compositor-session.sh"
# shellcheck source=clipboard-lib.sh
. "$script_dir/clipboard-lib.sh"

compositor="$(detect_compositor)"

case "$compositor" in
  kde)
    exec "$script_dir/clipboard-status-kde.sh"
    ;;
  hyprland)
    exec "$script_dir/clipboard-status-cliphist.sh"
    ;;
  *)
    if cliphist_available; then
      exec "$script_dir/clipboard-status-cliphist.sh"
    fi
    if kde_klipper_available; then
      exec "$script_dir/clipboard-status-kde.sh"
    fi
    printf '{"text":"󰅌","class":"unknown","alt":"unknown","tooltip":"No clipboard manager found"}\n'
    ;;
esac
