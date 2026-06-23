#!/usr/bin/env sh
set -eu

log() {
  logger -t waybar-healthcheck -- "$*"
}

restart_waybar() {
  systemctl --user reset-failed waybar >/dev/null 2>&1 || true
  systemctl --user restart waybar >/dev/null 2>&1 || systemctl --user start waybar >/dev/null 2>&1 || true
}

if ! timeout 2 systemctl --user is-active --quiet waybar; then
  log "waybar inactive; restarting"
  restart_waybar
  exit 0
fi

pid="$(timeout 2 systemctl --user show waybar -p MainPID --value 2>/dev/null || printf '0')"
if [ -z "$pid" ] || [ "$pid" = "0" ] || [ ! -d "/proc/$pid" ]; then
  log "waybar missing main pid; restarting"
  restart_waybar
  exit 0
fi

start_ts="$(timeout 2 systemctl --user show waybar -p ExecMainStartTimestamp --value 2>/dev/null || true)"
if [ -z "$start_ts" ]; then
  start_ts='45 seconds ago'
fi

# Cursor error bursts correlate with UI hangs in this setup.
arrow_errors="$(timeout 2 journalctl --user -u waybar --since "$start_ts" --no-pager 2>/dev/null \
  | grep -F 'Unable to load arrow from the cursor theme' \
  | wc -l | tr -d ' ')"
if [ "${arrow_errors:-0}" -ge 6 ]; then
  log "detected arrow cursor error burst (${arrow_errors}); restarting"
  restart_waybar
  exit 0
fi

# If Waybar accumulates many zombie children, log but do not restart.
# Background refresh in module exec scripts can leave transient [bash] zombies;
# restarting waybar for this causes visible reload loops without fixing root cause.
zombies="$(ps -eo ppid,stat,cmd 2>/dev/null | awk -v p="$pid" '$1==p && $2 ~ /^Z/ {count++} END {print count+0}')"
if [ "${zombies:-0}" -ge 20 ]; then
  sample="$(ps -eo ppid,stat,cmd 2>/dev/null | awk -v p="$pid" '$1==p && $2 ~ /^Z/ {print $0}' | head -3 | tr '\n' ' ')"
  log "zombie child accumulation (${zombies}); not restarting ${sample}"
fi

exit 0
