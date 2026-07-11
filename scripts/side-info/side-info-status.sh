#!/usr/bin/env sh
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="$(dirname "$0")"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-side-graphs"
state_file="$state_dir/info-tab"
mode="${1:-line1}"

. "$WAYBAR_SCRIPTS/lib/side-info-helpers.sh"

current_tab() {
  if [ -f "$state_file" ]; then
    tab="$(cat "$state_file" 2>/dev/null || true)"
    case "$tab" in
      docker|updates|stats|network|runtimes)
        printf '%s' "$tab"
        return
        ;;
    esac
  fi
  printf 'stats'
}

tab="$(current_tab)"

case "$tab" in
  docker)
    output="$($script_dir/side-info-docker-tab.sh 2>/dev/null || true)"
    ;;
  updates)
    output="$($script_dir/side-info-updates-tab.sh 2>/dev/null || true)"
    ;;
  stats)
    output="$($script_dir/side-info-stats-tab.sh 2>/dev/null || true)"
    ;;
  network)
    output="$($script_dir/side-info-network-tab.sh 2>/dev/null || true)"
    ;;
  runtimes)
    output="$($script_dir/side-info-runtimes-tab.sh 2>/dev/null || true)"
    ;;
  *)
    output=''
    ;;
esac

if [ -z "$output" ]; then
  emit_line "Info unavailable" "Info panel data unavailable" "disabled"
  exit 0
fi

json=$(printf '%s' "$output" | jq -c --arg mode "$mode" '
  {
    text: ((.[$mode] // "") | if . == "" then "-" else . end),
    tooltip: (.tooltip // ""),
    class: (.class // "normal")
  }
' 2>/dev/null || echo "")

if [ -z "$json" ]; then
  json='{"text":"-","tooltip":"Info panel data format error","class":"disabled"}'
fi

printf '%s\n' "$json"
