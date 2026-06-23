#!/usr/bin/env sh
# Signal Waybar modules and optionally invalidate cache files first.
# Usage: waybar-signal.sh <RTMIN offset> [cache-file...]
set -eu

signal="${1:-}"
[ -n "$signal" ] || exit 0
shift

for file in "$@"; do
  [ -n "$file" ] || continue
  rm -f "$file" 2>/dev/null || true
done

pkill -x -RTMIN+"$signal" waybar >/dev/null 2>&1 || true
