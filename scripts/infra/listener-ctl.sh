#!/usr/bin/env sh
# Start/stop singleton Waybar listener daemons.
set -eu

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"

KNOWN_LISTENERS="privacy kde-activewindow hypr-workspaces device-notifier vpn-tailscale album-art notify-sanitize"

stop_listener() {
  lock_name="$1"
  lock_dir="$runtime_dir/waybar-dock-listener-${lock_name}.lock.d"
  lock_pid_file="$lock_dir/pid"

  # Prefer stopping the transient unit (escapes oneshot healthcheck cgroup).
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user stop "waybar-listener-${lock_name}.service" >/dev/null 2>&1 || true
    systemctl --user stop "waybar-listener-${lock_name}.scope" >/dev/null 2>&1 || true
  fi

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
    # Prefer a transient Type=exec service so listeners escape the
    # waybar-healthcheck oneshot cgroup (setsid alone does not). Fall back
    # when systemd --user is unavailable (CI sandboxes, no session bus).
    started=0
    if command -v systemd-run >/dev/null 2>&1; then
      if systemd-run --user --collect --quiet \
        --unit="waybar-listener-${lock_name}" \
        --service-type=exec \
        --property=Restart=no \
        -- "$script" >/dev/null 2>&1; then
        started=1
      fi
    fi
    if [ "$started" -eq 0 ]; then
      if command -v setsid >/dev/null 2>&1; then
        setsid -f "$script" >/dev/null 2>&1 </dev/null || true
      else
        nohup "$script" >/dev/null 2>&1 &
      fi
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
