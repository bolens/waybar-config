#!/usr/bin/env sh
# Launch a command detached from Waybar so reload/restart does not terminate it.
# Usage:
#   app-open.sh cmd [args...]
#   app-open.sh --shell 'command chain'
set -eu

# Waybar runs under a user service and systemd-run scopes do not inherit the
# compositor's X11/Wayland auth. Pull those vars from Xwayland when missing.
graphical_env() {
  runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
  export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
  export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

  if [ -z "${WAYLAND_DISPLAY:-}" ] || [ -z "${DISPLAY:-}" ] || [ -z "${XAUTHORITY:-}" ]; then
    xwayland_pid=$(pgrep -x Xwayland 2>/dev/null | head -1 || true)
    if [ -n "$xwayland_pid" ] && [ -r "/proc/$xwayland_pid/environ" ]; then
      env_block=$(tr '\0' '\n' < "/proc/$xwayland_pid/environ" 2>/dev/null || echo "")
      if [ -z "${WAYLAND_DISPLAY:-}" ]; then
        WAYLAND_DISPLAY=$(printf '%s\n' "$env_block" | sed -n 's/^WAYLAND_DISPLAY=//p' | head -1)
      fi
      if [ -z "${DISPLAY:-}" ]; then
        DISPLAY=$(printf '%s\n' "$env_block" | sed -n 's/^DISPLAY=//p' | head -1)
      fi
      if [ -z "${XAUTHORITY:-}" ]; then
        XAUTHORITY=$(printf '%s\n' "$env_block" | sed -n 's/^XAUTHORITY=//p' | head -1)
      fi
    fi
  fi

  export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
  export DISPLAY="${DISPLAY:-:0}"

  if [ -z "${XAUTHORITY:-}" ]; then
    XAUTHORITY=$(ls -1t "$runtime_dir"/xauth_* 2>/dev/null | head -1 || true)
    [ -n "$XAUTHORITY" ] && export XAUTHORITY
  fi

  if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
  fi

  export STEAM_ZENITY="${STEAM_ZENITY:-$HOME/.local/bin/steam-host-dialog}"
  export GTK2_RC_FILES="${GTK2_RC_FILES:-/usr/share/themes/Adwaita/gtk-2.0/gtkrc}"
}

systemd_graphical_args() {
  graphical_env
  set -- \
    --setenv=WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
    --setenv=DISPLAY="$DISPLAY" \
    --setenv=XDG_DATA_HOME="$XDG_DATA_HOME" \
    --setenv=XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    --setenv=XDG_CACHE_HOME="$XDG_CACHE_HOME" \
    --setenv=XDG_STATE_HOME="$XDG_STATE_HOME"
  [ -n "${XAUTHORITY:-}" ] && set -- "$@" --setenv=XAUTHORITY="$XAUTHORITY"
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && set -- "$@" --setenv=DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
  set -- "$@" --setenv=STEAM_ZENITY="$STEAM_ZENITY" --setenv=GTK2_RC_FILES="$GTK2_RC_FILES"
  printf '%s\n' "$@"
}

app_launch_log() {
  mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
  printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/waybar/app-launch.log"
}

launch_detached() {
  graphical_env
  log_file="$(app_launch_log)"

  if command -v systemd-run >/dev/null 2>&1; then
    # shellcheck disable=SC2046
    if systemd-run --user --scope --collect --no-block $(systemd_graphical_args) \
      sh -c 'log_file="$1"; shift; exec "$@" >>"$log_file" 2>&1' _ "$log_file" "$@" >/dev/null 2>&1; then
      return 0
    fi
  fi

  if command -v setsid >/dev/null 2>&1; then
    setsid -f sh -c 'exec "$@" >>"$1" 2>&1' _ "$log_file" "$@" &
    return 0
  fi

  nohup sh -c 'exec "$@" >>"$1" 2>&1' _ "$log_file" "$@" &
}

if [ "${1:-}" = "--shell" ]; then
  shift
  if [ $# -lt 1 ]; then
    exit 64
  fi
  launch_detached sh -lc "$1"
  exit 0
fi

if [ $# -lt 1 ]; then
  exit 64
fi

launch_detached "$@"
