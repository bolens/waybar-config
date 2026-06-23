#!/usr/bin/env sh
# Ensure only one dock-windows listener runs per compositor backend.
set -eu

listener_name="$1"
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
