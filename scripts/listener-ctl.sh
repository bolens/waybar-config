#!/usr/bin/env sh
# Start/stop singleton Waybar listener daemons.
set -eu

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"

stop_listener() {
  lock_name="$1"
  lock_dir="$runtime_dir/waybar-dock-listener-${lock_name}.lock.d"
  lock_pid_file="$lock_dir/pid"

  if [ -f "$lock_pid_file" ]; then
    old_pid="$(sed -n '1p' "$lock_pid_file" 2>/dev/null || true)"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      kill "$old_pid" 2>/dev/null || true
      attempts=0
      while kill -0 "$old_pid" 2>/dev/null; do
        attempts=$((attempts + 1))
        [ "$attempts" -ge 15 ] && break
        sleep 0.1
      done
      if kill -0 "$old_pid" 2>/dev/null; then
        kill -9 "$old_pid" 2>/dev/null || true
      fi
    fi
  fi

  rm -rf "$lock_dir" 2>/dev/null || true
}

start_listener() {
  script="$1"
  lock_name="$2"

  stop_listener "$lock_name"
  if [ -x "$script" ]; then
    if command -v setsid >/dev/null 2>&1; then
      setsid -f "$script" >/dev/null 2>&1 < /dev/null || true
    else
      nohup "$script" >/dev/null 2>&1 &
    fi
  fi
}

case "${1:-}" in
  start)
    shift
    start_listener "$@"
    ;;
  stop)
    shift
    stop_listener "$@"
    ;;
  *)
    printf 'Usage: %s start|stop <script> <lock-name>\n' "$0" >&2
    exit 1
    ;;
esac
