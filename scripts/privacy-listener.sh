#!/usr/bin/env bash
# Keep privacy indicator cache warm (single instance).
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/privacy-status.json"
poll_seconds=15

# shellcheck source=dock-windows-listener-lock.sh
. "$script_dir/dock-windows-listener-lock.sh" privacy
# shellcheck source=privacy-status.sh
# collect_privacy_json is defined in privacy-status.sh --refresh path

mkdir -p "$cache_dir"

prev_state=""

update_privacy() {
  json="$("$script_dir/privacy-status.sh" --refresh 2>/dev/null || true)"
  if [ -n "$json" ]; then
    if [ "$json" != "$prev_state" ]; then
      tmp="${cache_file}.tmp.$$"
      printf '%s\n' "$json" >"$tmp"
      mv "$tmp" "$cache_file"
      pkill -x -RTMIN+17 waybar >/dev/null 2>&1 || true
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
  "$script_dir/mic-status.sh" --refresh >/dev/null 2>&1 || true
  pkill -x -RTMIN+7 waybar >/dev/null 2>&1 || true
}

# Initial update
update_privacy
update_mic

# Create FIFO for trigger events
fifo="${cache_dir}/privacy-trigger.$$.fifo"
rm -f "$fifo"
mkfifo "$fifo"

cleanup() {
  rm -f "$fifo" 2>/dev/null || true
  pkill -P "$$" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Start PulseAudio listener writing to FIFO
if command -v pactl >/dev/null 2>&1; then
  ( pactl subscribe 2>/dev/null | grep --line-buffered -E "source|source-output|sink|sink-input" > "$fifo" 2>/dev/null || true ) &
fi

# Start fallback periodic timer writing to FIFO
(
  while true; do
    sleep "$poll_seconds"
    echo "tick" > "$fifo" 2>/dev/null || true
  done
) &

# Read and process triggers
exec 3< "$fifo"
while read -r line <&3; do
  case "$line" in
    *source*|*tick*)
      update_mic &
      ;;
  esac
  update_privacy
done
