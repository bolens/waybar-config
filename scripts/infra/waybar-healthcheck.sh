#!/usr/bin/env sh
# Timer-driven heal: restart dead waybar and revive expected listeners (privacy, dock, …).
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"

# Source compositor detection
if [ -f "$WAYBAR_SCRIPTS/lib/compositor-session.sh" ]; then
  . "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
fi

log() {
  logger -t waybar-healthcheck -- "$*"
}

restart_waybar() {
  systemctl --user reset-failed waybar >/dev/null 2>&1 || true
  systemctl --user restart waybar >/dev/null 2>&1 || systemctl --user start waybar >/dev/null 2>&1 || true
}

is_listener_running() {
  lock_name="$1"
  lock_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-dock-listener-${lock_name}.lock.d"
  lock_pid_file="$lock_dir/pid"
  if [ -f "$lock_pid_file" ]; then
    pid="$(sed -n '1p' "$lock_pid_file" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

check_and_heal_listeners() {
  # 1. Privacy listener is required on all compositors
  if ! is_listener_running "privacy"; then
    log "privacy listener dead; restarting"
    "$script_dir/listener-ctl.sh" start "$WAYBAR_SCRIPTS/listeners/privacy-listener.sh" privacy
  fi

  # 2. Device notifier (removable storage) on all compositors
  if ! is_listener_running "device-notifier"; then
    if [ -x "$WAYBAR_SCRIPTS/listeners/device-notifier-listener.sh" ]; then
      log "device-notifier listener dead; restarting"
      "$script_dir/listener-ctl.sh" start "$WAYBAR_SCRIPTS/listeners/device-notifier-listener.sh" device-notifier
    fi
  fi

  # 2b. VPN / Tailscale tunnel watcher
  if ! is_listener_running "vpn-tailscale"; then
    if [ -x "$WAYBAR_SCRIPTS/listeners/vpn-tailscale-listener.sh" ]; then
      log "vpn-tailscale listener dead; restarting"
      "$script_dir/listener-ctl.sh" start "$WAYBAR_SCRIPTS/listeners/vpn-tailscale-listener.sh" vpn-tailscale
    fi
  fi

  # 2c. Album-art MPRIS follower
  if ! is_listener_running "album-art"; then
    if [ -x "$WAYBAR_SCRIPTS/listeners/album-art-listener.sh" ]; then
      log "album-art listener dead; restarting"
      "$script_dir/listener-ctl.sh" start "$WAYBAR_SCRIPTS/listeners/album-art-listener.sh" album-art
    fi
  fi

  # 3. Compositor-specific listener
  comp="$(detect_compositor)"
  if [ "$comp" = "hyprland" ]; then
    if ! is_listener_running "hypr-workspaces"; then
      log "hypr-workspaces listener dead; restarting"
      "$script_dir/listener-ctl.sh" start "$WAYBAR_SCRIPTS/listeners/workspaces-hyprland-listener.sh" hypr-workspaces
    fi
  elif [ "$comp" = "kde" ]; then
    if ! is_listener_running "kde-activewindow"; then
      log "kde-activewindow listener dead; restarting"
      "$script_dir/listener-ctl.sh" start "$WAYBAR_SCRIPTS/listeners/active-window-listener-kde.py" kde-activewindow
    fi
  fi
}

# 1. Verify Waybar is active
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

# 2. Verify cursor load errors from standard file-based logging fallback
log_file="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/waybar.log"
arrow_errors=0
if [ -f "$log_file" ]; then
  arrow_errors="$(grep -F 'Unable to load arrow from the cursor theme' "$log_file" 2>/dev/null | wc -l | tr -d ' ')"
fi

if [ "${arrow_errors:-0}" -ge 6 ]; then
  log "detected arrow cursor error burst (${arrow_errors}); restarting"
  restart_waybar
  exit 0
fi

# 3. Check for zombie child accumulation
zombies="$(ps -eo ppid,stat,cmd 2>/dev/null | awk -v p="$pid" '$1==p && $2 ~ /^Z/ {count++} END {print count+0}')"
if [ "${zombies:-0}" -ge 20 ]; then
  sample="$(ps -eo ppid,stat,cmd 2>/dev/null | awk -v p="$pid" '$1==p && $2 ~ /^Z/ {print $0}' | head -3 | tr '\n' ' ')"
  log "zombie child accumulation (${zombies}); not restarting ${sample}"
fi

# 4. Verify and self-heal background listener processes
check_and_heal_listeners

exit 0
