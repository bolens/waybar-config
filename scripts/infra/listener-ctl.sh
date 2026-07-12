#!/usr/bin/env sh
# Start/stop singleton Waybar listener daemons.
set -eu

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"

KNOWN_LISTENERS="privacy kde-activewindow hypr-workspaces device-notifier vpn-tailscale album-art"

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

stop_all_listeners() {
  for name in $KNOWN_LISTENERS; do
    stop_listener "$name"
  done
}

start_listener() {
  script="$1"
  lock_name="$2"

  stop_listener "$lock_name"
  if [ -x "$script" ]; then
    # Keep listeners in the same session tree when possible; lock files still
    # track PIDs for ExecStop / healthcheck. Avoid setsid so systemd stop can
    # still clean up via stop-all even if cgroup reaping misses them.
    if command -v setsid >/dev/null 2>&1; then
      # setsid is retained so listeners survive launch.sh's final `exec waybar`,
      # but stop-all + healthcheck are the lifecycle owners.
      setsid -f "$script" >/dev/null 2>&1 </dev/null || true
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
  stop-all)
    stop_all_listeners
    ;;
  *)
    printf 'Usage: %s start|stop|stop-all [<script> <lock-name>]\n' "$0" >&2
    exit 1
    ;;
esac
