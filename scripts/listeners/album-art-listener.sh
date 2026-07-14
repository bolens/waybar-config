#!/usr/bin/env bash
# Push album-art updates when MPRIS metadata changes (playerctl --follow).
#
# Lifecycle: started by waybar-launch.sh / healed by waybar-healthcheck.sh via
# listener-ctl.sh (lock name: album-art). Pairs with signals.album_art and
# module_intervals.album_art="once" so Waybar re-execs on signal, not a busy poll.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/album-art-status.json"
poll_seconds=30

# shellcheck source=dock-windows-listener-lock.sh
WAYBAR_LISTENER_LOCK_NAME=album-art
. "$script_dir/dock-windows-listener-lock.sh"

mkdir -p "$cache_dir"
# Drop orphaned FIFOs from prior crash loops (PID in name; process gone).
rm -f "$cache_dir"/album-art-trigger.*.fifo 2>/dev/null || true

prev=""

refresh_art() {
  local json
  json="$("$WAYBAR_SCRIPTS/media/album-art-status.sh" --refresh 2>/dev/null || true)"
  if [ -n "$json" ] && [ "$json" != "$prev" ]; then
    tmp="${cache_file}.tmp.$$"
    printf '%s\n' "$json" >"$tmp"
    mv "$tmp" "$cache_file"
    "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" album_art 2>/dev/null || true
    prev="$json"
  elif [ -n "$json" ] && [ ! -f "$cache_file" ]; then
    printf '%s\n' "$json" >"$cache_file"
    prev="$json"
  fi
}

refresh_art

if ! command -v playerctl >/dev/null 2>&1; then
  # No playerctl: keep a slow poll so enabling later still works.
  while true; do
    sleep "$poll_seconds"
    refresh_art
  done
fi

fifo="${cache_dir}/album-art-trigger.$$.fifo"
rm -f "$fifo"
mkfifo "$fifo"

waybar_listener_cleanup() {
  exec 3<&- 2>/dev/null || true
  rm -f "$fifo" 2>/dev/null || true
  pkill -P "$$" 2>/dev/null || true
}

# Follow metadata (art URL / track changes). Debounce via FIFO reader.
(
  playerctl --follow metadata --format '{{mpris:artUrl}}|{{title}}|{{artist}}|{{status}}' 2>/dev/null \
    | while read -r _; do
      echo "meta" >"$fifo" 2>/dev/null || true
    done
) &

(
  while true; do
    sleep "$poll_seconds"
    echo "tick" >"$fifo" 2>/dev/null || true
  done
) &

# Open RDWR so the reader never EOFs between ephemeral writers and we don't
# deadlock waiting for a writer before the keep-alive open.
exec 3<>"$fifo"
while read -r _line <&3; do
  refresh_art
done
