#!/usr/bin/env bash
# Shared helpers for compositor-aware notification modules.

: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
signal_waybar() {
  pkill -x -RTMIN+10 waybar >/dev/null 2>&1 || true
}

kde_notifications_inhibited() {
  timeout 2 qdbus6 org.kde.plasmashell /org/freedesktop/Notifications \
    org.freedesktop.DBus.Properties.Get \
    org.freedesktop.Notifications Inhibited 2>/dev/null \
    | rg -Fq true
}

kde_toggle_dnd() {
  timeout 2 qdbus6 org.kde.kglobalaccel /component/plasmashell \
    org.kde.kglobalaccel.Component.invokeShortcut \
    "toggle do not disturb" >/dev/null 2>&1 || true
}

kde_notifications_running() {
  pid=""
  for pid in $(pgrep -x plasmawindowed 2>/dev/null || true); do
    if tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | rg -Fq 'org.kde.plasma.notifications'; then
      printf '%s' "$pid"
      return 0
    fi
  done
  return 1
}

kde_open_notifications() {
  local script_dir
  script_dir="$(dirname "${BASH_SOURCE[0]:-$0}")"
  # Send SIGUSR1 to python listener to reset unread count badge in waybar
  pkill -USR1 -f "active-window-listener-kde.py" >/dev/null 2>&1 || true
  # Launch the Rofi notification center helper
  "$WAYBAR_SCRIPTS/notifications/kde-notifications-rofi.sh" &
}

kde_open_settings() {
  local script_dir
  script_dir="$(dirname "${BASH_SOURCE[0]:-$0}")"
  if [ -f "$script_dir/waybar-settings.sh" ]; then
    # shellcheck source=waybar-settings.sh
    . "$script_dir/waybar-settings.sh"
  fi
  # shellcheck source=app-open-lib.sh
  . "$WAYBAR_SCRIPTS/lib/app-open-lib.sh"
  local cmd
  cmd=$(waybar_settings_get '.apps.notifications_settings' 'systemsettings6 kcm_notifications')
  if [ -n "$cmd" ] && [ -x "$WAYBAR_SCRIPTS/tools/app-open.sh" ]; then
    waybar_app_open "$cmd"
    return 0
  fi
  if command -v systemsettings6 >/dev/null 2>&1; then
    systemsettings6 kcm_notifications
    return 0
  fi
  if command -v kcmshell6 >/dev/null 2>&1; then
    kcmshell6 kcm_notifications
    return 0
  fi
  return 1
}

mako_dnd_active() {
  command -v makoctl >/dev/null 2>&1 \
    && makoctl mode 2>/dev/null | rg -Fq 'do-not-disturb'
}

mako_visible_count() {
  if ! command -v makoctl >/dev/null 2>&1; then
    printf '0'
    return
  fi
  makoctl list -j 2>/dev/null | jq 'length' 2>/dev/null || printf '0'
}
