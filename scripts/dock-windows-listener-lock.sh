#!/usr/bin/env sh
# Ensure only one dock-windows listener runs per compositor backend.
#
# Must be sourced (sets EXIT trap in the listener). Dash ignores arguments to
# `.`, so pass the lock name via WAYBAR_LISTENER_LOCK_NAME (bash still accepts $1).
set -eu

listener_name="${WAYBAR_LISTENER_LOCK_NAME:-${1-}}"
if [ -z "$listener_name" ]; then
  printf 'dock-windows-listener-lock: set WAYBAR_LISTENER_LOCK_NAME or pass name as \$1\n' >&2
  exit 1
fi

lock_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-dock-listener-${listener_name}.lock.d"
lock_pid_file="$lock_dir/pid"

if ! mkdir "$lock_dir" 2>/dev/null; then
  if [ -f "$lock_pid_file" ]; then
    old_pid="$(sed -n '1p' "$lock_pid_file" 2>/dev/null || true)"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      exit 0
    fi
  fi
  rm -rf "$lock_dir"
  mkdir "$lock_dir" 2>/dev/null || exit 0
fi

printf '%s\n' "$$" >"$lock_pid_file"
trap 'rm -f "$lock_pid_file"; rmdir "$lock_dir" 2>/dev/null || true' EXIT INT TERM
