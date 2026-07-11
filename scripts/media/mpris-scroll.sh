#!/usr/bin/env bash
# Continuous scrolling MPRIS module using zscroll and playerctl.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="$(CDPATH="" cd -- "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

# Ensure playerctl is available
if ! command -v playerctl >/dev/null 2>&1; then
  echo ""
  exit 0
fi

# Load config overrides
enable_scroll=$(waybar_settings_get '.audio.mpris_zscroll' 'true')
mpris_max_length=$(waybar_settings_get '.audio.mpris_max_length' '32')
scroll_delay=$(waybar_settings_get '.audio.mpris_scroll_delay' '0.3')

# Run in loop to handle player restarts
if [ "$enable_scroll" = "true" ] && command -v zscroll >/dev/null 2>&1; then
  while true; do
    if playerctl status >/dev/null 2>&1; then
      # Prefix each output line with the music icon.
      # zscroll scrolls the text after the formatting dynamically.
      zscroll -l "$mpris_max_length" \
        --delay "$scroll_delay" \
        --match-command "playerctl status 2>/dev/null" \
        --match-text "Playing" "--scroll 1" \
        --match-text "Paused" "--scroll 0" \
        --update-check true \
        'playerctl metadata --format "󰝚 {{title}} - {{artist}}" 2>/dev/null' 2>/dev/null || true
    else
      # Output empty string so Waybar hides the module
      echo ""
      sleep 4
    fi
  done
else
  # Static fallback loop when zscroll is disabled or not installed
  last_metadata=""
  while true; do
    if playerctl status >/dev/null 2>&1; then
      meta=$(playerctl metadata --format "󰝚 {{title}} - {{artist}}" 2>/dev/null || echo "")
      meta=$(echo "$meta" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')

      if [ "$meta" != "$last_metadata" ]; then
        if [ -n "$meta" ] && [ "$meta" != "󰝚  - " ]; then
          if [ ${#meta} -gt "$mpris_max_length" ]; then
            trunc_len=$((mpris_max_length - 3))
            [ $trunc_len -lt 1 ] && trunc_len=1
            truncated="${meta:0:$trunc_len}..."
          else
            truncated="$meta"
          fi
          echo "$truncated"
        else
          echo ""
        fi
        last_metadata="$meta"
      fi
      sleep 1
    else
      if [ -n "$last_metadata" ]; then
        echo ""
        last_metadata=""
      fi
      sleep 4
    fi
  done
fi
