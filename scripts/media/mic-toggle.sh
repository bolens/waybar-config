#!/usr/bin/env sh
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

signal_waybar() {
  # Prefer signals.mic from settings (default 7).
  rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/waybar/mic-status.json" 2>/dev/null || true
  "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" mic
}

timeout 2 wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle || true

v=$(timeout 2 wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null || true)
compositor=$(detect_compositor)

if printf '%s' "$v" | rg -Fq MUTED; then
  case "$compositor" in
    hyprland)
      if command -v hyprctl >/dev/null 2>&1; then
        hyprctl notify 0 2500 "rgb(f38ba8)" "fontsize:20  MIC MUTED" >/dev/null 2>&1 || true
      else
        notify-send -t 2500 -u critical -i microphone-sensitivity-muted "Mic" " MUTED" 2>/dev/null || true
      fi
      ;;
    *) notify-send -t 2500 -u critical -i microphone-sensitivity-muted "Mic" " MUTED" 2>/dev/null || true ;;
  esac
else
  pct=$(printf '%s' "$v" | awk '{printf "%d", $2*100}')
  case "$compositor" in
    hyprland)
      if command -v hyprctl >/dev/null 2>&1; then
        hyprctl notify 5 2500 "rgb(a6e3a1)" "fontsize:20  MIC LIVE — ${pct}%" >/dev/null 2>&1 || true
      else
        notify-send -t 2500 -i microphone-sensitivity-high "Mic" " LIVE — ${pct}%" 2>/dev/null || true
      fi
      ;;
    *) notify-send -t 2500 -i microphone-sensitivity-high "Mic" " LIVE — ${pct}%" 2>/dev/null || true ;;
  esac
fi

signal_waybar
