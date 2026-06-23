#!/usr/bin/env sh
# Continuous scrolling MPRIS module using zscroll and playerctl.
set -eu

# Ensure playerctl and zscroll are available
if ! command -v playerctl >/dev/null 2>&1 || ! command -v zscroll >/dev/null 2>&1; then
  echo ""
  exit 0
fi

# Run in loop to handle player restarts
while true; do
  if playerctl status >/dev/null 2>&1; then
    # Prefix each output line with the music icon.
    # zscroll scrolls the text after the formatting dynamically.
    zscroll -l 28 \
            --delay 0.3 \
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
