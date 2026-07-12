#!/usr/bin/env bash
# Stream Deck module clicks — taskbar-style activate (raise existing window, else launch).
#   open|""  — focus Stream Deck UI if running, otherwise start it (left-click)
#   restart  — restart configured user service (right-click)
#   refresh  — refresh status cache + signal (middle-click)
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

# shellcheck source=../../lib/waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck source=../../lib/compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

action="${1:-open}"
service="$(waybar_settings_get '.streamdeck.service_name' 'app-streamdeck-ui@autostart.service')"
# Prefer a cache-dir log so a root-owned ~/.streamdeck_ui.log cannot block launches.
log_file="${STREAMDECK_UI_LOG_FILE:-${XDG_CACHE_HOME:-$HOME/.cache}/waybar/streamdeck-ui.log}"
mkdir -p "$(dirname "$log_file")"
export STREAMDECK_UI_LOG_FILE="$log_file"

streamdeck_running() {
  pgrep -f '(^|/)streamdeck( |$)' >/dev/null 2>&1 \
    || pgrep -f '/usr/bin/python.*/usr/bin/streamdeck' >/dev/null 2>&1
}

# Raise an already-open Stream Deck UI window (like Plasma task manager / tray Configure).
# A second `streamdeck` process hits /tmp/streamdeck_ui.lock and exits with no UI.
focus_streamdeck_window() {
  local session title_re id
  session="$(detect_compositor)"
  title_re='Stream Deck UI'

  case "$session" in
    kde)
      if ! command -v qdbus6 >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        return 1
      fi
      id="$(
        "$WAYBAR_SCRIPTS/dock/dock-windows-query.sh" 2>/dev/null \
          | jq -r --arg t "$title_re" '.[] | select(.title == $t) | .id' \
          | head -n1
      )"
      if [[ -z "$id" || "$id" == "null" ]]; then
        # Broader match if the title gains a suffix.
        id="$(
          "$WAYBAR_SCRIPTS/dock/dock-windows-query.sh" 2>/dev/null \
            | jq -r --arg t "$title_re" '.[] | select(.title | test($t)) | .id' \
            | head -n1
        )"
      fi
      [[ -n "$id" && "$id" != "null" ]] || return 1
      timeout 2 qdbus6 org.kde.KWin /WindowsRunner org.kde.krunner1.Run "$id" "" >/dev/null 2>&1
      ;;
    hyprland)
      if ! command -v hyprctl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        return 1
      fi
      id="$(
        hyprctl clients -j 2>/dev/null \
          | jq -r --arg t "$title_re" '
              .[]
              | select((.title // "") == $t or ((.title // "") | test($t))
                       or ((.class // "") | test("streamdeck"; "i")))
              | .address
            ' \
          | head -n1
      )"
      [[ -n "$id" && "$id" != "null" ]] || return 1
      hyprctl dispatch focuswindow "address:$id" >/dev/null 2>&1
      hyprctl dispatch bringactivetotop >/dev/null 2>&1 || true
      ;;
    *)
      if command -v wmctrl >/dev/null 2>&1; then
        wmctrl -a "$title_re" >/dev/null 2>&1 && return 0
      fi
      return 1
      ;;
  esac
}

launch_streamdeck() {
  # Prefer the autostart unit when present (idempotent if already running).
  if [[ -n "$service" ]] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user start "$service" >/dev/null 2>&1 || true
  fi
  # Plasma-native desktop launch (same .desktop as the taskbar/launcher icon).
  if command -v kioclient >/dev/null 2>&1 && [[ -f /usr/share/applications/streamdeck-ui.desktop ]]; then
    exec "$WAYBAR_SCRIPTS/tools/app-open.sh" kioclient exec /usr/share/applications/streamdeck-ui.desktop
  fi
  if command -v gtk-launch >/dev/null 2>&1 && [[ -f /usr/share/applications/streamdeck-ui.desktop ]]; then
    exec "$WAYBAR_SCRIPTS/tools/app-open.sh" gtk-launch streamdeck-ui.desktop
  fi
  if command -v streamdeck >/dev/null 2>&1; then
    exec "$WAYBAR_SCRIPTS/tools/app-open.sh" streamdeck
  fi
  notify-send "Stream Deck" "streamdeck UI not found on PATH" 2>/dev/null || true
  exit 1
}

case "$action" in
  open | '')
    # Taskbar behavior: activate existing window first. Do NOT spawn a second
    # streamdeck — the app's file lock makes that a silent no-op.
    if focus_streamdeck_window; then
      exit 0
    fi
    if streamdeck_running; then
      # Process alive but window not listed (e.g. closed to tray). Restarting the
      # unit is the reliable way to show the UI again without a second instance.
      if [[ -n "$service" ]] && command -v systemctl >/dev/null 2>&1; then
        if systemctl --user restart "$service" >/dev/null 2>&1; then
          # Give the window a moment, then focus if it appears.
          sleep 0.4
          focus_streamdeck_window || true
          exit 0
        fi
      fi
    fi
    launch_streamdeck
    ;;
  restart)
    if [[ -n "$service" ]] && command -v systemctl >/dev/null 2>&1; then
      systemctl --user restart "$service" >/dev/null 2>&1 || true
    fi
    "$WAYBAR_SCRIPTS/services/devices/streamdeck-status.sh" --refresh >/dev/null 2>&1 || true
    sig="$(waybar_settings_get '.signals.streamdeck' '24')"
    "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" "$sig" >/dev/null 2>&1 || true
    ;;
  refresh)
    "$WAYBAR_SCRIPTS/services/devices/streamdeck-status.sh" --refresh >/dev/null 2>&1 || true
    sig="$(waybar_settings_get '.signals.streamdeck' '24')"
    "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" "$sig" >/dev/null 2>&1 || true
    ;;
  *)
    printf 'Usage: %s [open|restart|refresh]\n' "${0##*/}" >&2
    exit 64
    ;;
esac
