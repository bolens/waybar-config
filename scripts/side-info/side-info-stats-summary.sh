#!/usr/bin/env sh
# side-info-stats-summary.sh: Stats summary logic for side-info-status.sh

: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
script_dir="$(dirname "$0")"
. "$WAYBAR_SCRIPTS/lib/side-info-helpers.sh"

stats_summary() {
  # Stub: emit placeholder stats
  jq -cn \
    --arg line1 "Stats unavailable" \
    --arg line2 "-" \
    --arg line3 "-" \
    --arg line4 "-" \
    --arg tooltip "Stats module missing or not implemented" \
    --arg class "disabled" \
    '{line1:$line1, line2:$line2, line3:$line3, line4:$line4, tooltip:$tooltip, class:$class}'
}

stats_summary
