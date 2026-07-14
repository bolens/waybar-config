#!/usr/bin/env sh
# Signal Waybar modules and optionally invalidate cache files first.
#
# Usage: waybar-signal.sh <RTMIN offset|signals.* key> [cache-file...]
#
# Prefer a signals.* key (e.g. clipboard, mic) so click/libs stay aligned with
# generators and data/waybar-settings.jsonc. Numeric offsets still work for
# one-offs. Do not hardcode RTMIN+N in new code — if settings.signals.X changes,
# hardcoded pkill lines miss the module Waybar subscribed to.
#
# Unknown keys / missing compiled settings print a short stderr line (visible in
# journalctl --user -u waybar and ~/.cache/waybar/waybar.log) then exit 0 so
# click handlers never abort the shell pipeline.
set -eu

signal="${1:-}"
[ -n "$signal" ] || exit 0
shift

case "$signal" in
  *[!0-9]*)
    key="$signal"
    : "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
    settings="$WAYBAR_HOME/data/waybar-settings.json"
    if [ ! -f "$settings" ]; then
      printf 'waybar-signal: missing %s (run make generate); key=%s\n' \
        "$settings" "$key" >&2
      exit 0
    fi
    if ! command -v jq >/dev/null 2>&1; then
      printf 'waybar-signal: jq required to resolve signals.%s\n' "$key" >&2
      exit 0
    fi
    signal=$(jq -r --arg k "$key" '.signals[$k] // empty' "$settings" 2>/dev/null || true)
    if [ -z "$signal" ]; then
      printf 'waybar-signal: unknown key %s (not in signals.* of waybar-settings.json)\n' \
        "$key" >&2
      exit 0
    fi
    ;;
esac

for file in "$@"; do
  [ -n "$file" ] || continue
  rm -f "$file" 2>/dev/null || true
done

pkill -x -RTMIN+"$signal" waybar >/dev/null 2>&1 || true
