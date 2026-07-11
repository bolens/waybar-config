#!/usr/bin/env bash
# cliphist clipboard status for Waybar on Hyprland (long-running).
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
# shellcheck source=clipboard-lib.sh
. "$WAYBAR_SCRIPTS/lib/clipboard-lib.sh"

emit_cliphist_status() {
  if ! cliphist_available; then
    printf '{"text":"󰅌","class":"disabled","alt":"disabled","tooltip":"cliphist not installed"}\n'
    return 0
  fi

  count="$(cliphist_count)"
  latest="$(cliphist_latest)"
  print_clipboard_status "$count" "$latest" "cliphist"
}

emit_cliphist_status

