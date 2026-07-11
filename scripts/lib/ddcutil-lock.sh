#!/usr/bin/env sh
# Serialize ddcutil access across Waybar brightness scripts.
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
lock_dir="$cache_dir/ddcutil.lock"
stale_lock_seconds=45

with_ddcutil_lock() {
  attempts=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 150 ]; then
      now=$(date +%s)
      mtime=$(stat -c %Y "$lock_dir" 2>/dev/null || printf '%s' 0)
      if [ $((now - mtime)) -ge "$stale_lock_seconds" ] 2>/dev/null; then
        rm -rf "$lock_dir" 2>/dev/null || true
        attempts=0
        continue
      fi
      return 1
    fi
    sleep 0.02
  done

  "$@"
  status=$?
  rmdir "$lock_dir" 2>/dev/null || true
  return "$status"
}
