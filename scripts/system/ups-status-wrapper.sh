#!/usr/bin/env bash
# Resolve NUT target once per session; avoid settings merge on every UPS poll.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

nut_file="${XDG_RUNTIME_DIR:-/tmp}/waybar-nut-target"

if [ ! -f "$nut_file" ] || [ "${1:-}" = "--refresh" ]; then
  # shellcheck source=waybar-settings.sh
  . "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
  tmp="$nut_file.tmp.$$"
  waybar_services_nut_target >"$tmp"
  mv -f "$tmp" "$nut_file"
fi

exec env NUT_TARGET="$(cat "$nut_file")" "$WAYBAR_SCRIPTS/system/ups-status.sh" "$@"
