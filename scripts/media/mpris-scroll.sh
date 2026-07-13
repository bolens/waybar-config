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
scroll_delay=$(waybar_settings_get '.audio.mpris_scroll_delay' '0.8')

# Cap Waybar text updates — dual-output zscroll at 0.3s kills tooltips bar-wide
# (Alexays/Waybar#3910 / #4909).
emit_min_ms=500

emit_throttled() {
  local line="$1"
  local now_ms
  now_ms=$(date +%s%3N 2>/dev/null || echo 0)
  case "$now_ms" in '' | *[!0-9]*) now_ms=0 ;; esac
  if [ -n "${last_line:-}" ] && [ "$line" = "$last_line" ]; then
    return 0
  fi
  if [ "$now_ms" -gt 0 ] && [ "${last_emit_ms:-0}" -gt 0 ] \
    && [ $((now_ms - last_emit_ms)) -lt "$emit_min_ms" ]; then
    return 0
  fi
  last_line="$line"
  [ "$now_ms" -gt 0 ] && last_emit_ms=$now_ms
  printf '%s\n' "$line"
}

# Run in loop to handle player restarts
if [ "$enable_scroll" = "true" ] && command -v zscroll >/dev/null 2>&1; then
  while true; do
    if playerctl status >/dev/null 2>&1; then
      last_line=""
      last_emit_ms=0
      # Prefix each output line with the music icon.
      # zscroll scrolls the text after the formatting dynamically.
      zscroll -l "$mpris_max_length" \
        --delay "$scroll_delay" \
        --match-command "playerctl status 2>/dev/null" \
        --match-text "Playing" "--scroll 1" \
        --match-text "Paused" "--scroll 0" \
        --update-check true \
        'playerctl metadata --format "󰝚 {{title}} - {{artist}}" 2>/dev/null' 2>/dev/null \
        | while IFS= read -r line; do
          emit_throttled "$line"
        done || true
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
