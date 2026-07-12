#!/usr/bin/env sh
# Signal Waybar modules and optionally invalidate cache files first.
#
# Usage: waybar-signal.sh <RTMIN offset|signals.* key> [cache-file...]
#
# Prefer a signals.* key (e.g. clipboard, mic) so click/libs stay aligned with
# generators and data/waybar-settings.jsonc. Numeric offsets still work for
# one-offs. Do not hardcode RTMIN+N in new code — if settings.signals.X changes,
# hardcoded pkill lines miss the module Waybar subscribed to.
set -eu

signal="${1:-}"
[ -n "$signal" ] || exit 0
shift

case "$signal" in
  *[!0-9]*)
    : "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
    settings="$WAYBAR_HOME/data/waybar-settings.json"
    if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
      signal=$(jq -r --arg k "$signal" '.signals[$k] // empty' "$settings" 2>/dev/null || true)
    else
      signal=""
    fi
    [ -n "$signal" ] || exit 0
    ;;
esac

for file in "$@"; do
  [ -n "$file" ] || continue
  rm -f "$file" 2>/dev/null || true
done

pkill -x -RTMIN+"$signal" waybar >/dev/null 2>&1 || true
