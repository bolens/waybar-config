#!/usr/bin/env bash
# Keep privacy indicator cache warm (single instance).
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/privacy-status.json"
poll_seconds=15

# shellcheck source=dock-windows-listener-lock.sh
WAYBAR_LISTENER_LOCK_NAME=privacy
. "$script_dir/dock-windows-listener-lock.sh"
# shellcheck source=privacy-status.sh
# collect_privacy_json is defined in privacy-status.sh --refresh path

mkdir -p "$cache_dir"
rm -f "$cache_dir"/privacy-trigger.*.fifo 2>/dev/null || true

prev_state=""

update_privacy() {
  json="$("$WAYBAR_SCRIPTS/services/security/privacy-status.sh" --refresh 2>/dev/null || true)"
  if [ -n "$json" ]; then
    if [ "$json" != "$prev_state" ]; then
      tmp="${cache_file}.tmp.$$"
      printf '%s\n' "$json" >"$tmp"
      mv "$tmp" "$cache_file"
      "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" privacy
      prev_state="$json"
    elif [ ! -f "$cache_file" ]; then
      tmp="${cache_file}.tmp.$$"
      printf '%s\n' "$json" >"$tmp"
      mv "$tmp" "$cache_file"
      prev_state="$json"
    fi
  fi
}

update_mic() {
  "$WAYBAR_SCRIPTS/media/mic-status.sh" --refresh >/dev/null 2>&1 || true
  "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" mic
}

# Initial update
update_privacy
update_mic

# Create FIFO for trigger events
fifo="${cache_dir}/privacy-trigger.$$.fifo"
rm -f "$fifo"
mkfifo "$fifo"

waybar_listener_cleanup() {
  exec 3<&- 2>/dev/null || true
  rm -f "$fifo" 2>/dev/null || true
  pkill -P "$$" 2>/dev/null || true
}

# Start PulseAudio listener writing to FIFO
if command -v pactl >/dev/null 2>&1; then
  (pactl subscribe 2>/dev/null | grep --line-buffered -E "source|source-output|sink|sink-input" >"$fifo" 2>/dev/null || true) &
fi

# Start fallback periodic timer writing to FIFO
(
  while true; do
    sleep "$poll_seconds"
    echo "tick" >"$fifo" 2>/dev/null || true
  done
) &

# Open RDWR so read never EOFs if pactl/grep exits between ticks.
exec 3<>"$fifo"
while read -r line <&3; do
  case "$line" in
    *source* | *tick*)
      update_mic &
      ;;
  esac
  update_privacy
done
