#!/usr/bin/env bash
# Compositor-aware notification center actions for Waybar.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
# shellcheck source=notifications-lib.sh
. "$WAYBAR_SCRIPTS/lib/notifications-lib.sh"

if [ -f "$WAYBAR_SCRIPTS/lib/waybar-settings.sh" ]; then
  . "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
else
  . "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
fi

action="${1:-open}"
compositor="$(detect_compositor)"

signal_refresh() {
  signal_waybar
}

hyprland_open() {
  if command -v swaync-client >/dev/null 2>&1; then
    swaync-client -t -sw
    signal_refresh
    return 0
  fi

  if command -v makoctl >/dev/null 2>&1; then
    if command -v rofi >/dev/null 2>&1; then
      history="$(makoctl history -j 2>/dev/null || printf '[]')"
      count="$(printf '%s' "$history" | jq 'length' 2>/dev/null || printf '0')"
      if [ "$count" -eq 0 ] 2>/dev/null; then
        notify-send "Notifications" "No notification history (install SwayNC for a full center)" 2>/dev/null || true
        return 0
      fi
      notif_theme=$(waybar_settings_get '.rofi.theme' '')
      notif_theme="${notif_theme/\$WAYBAR_HOME/$WAYBAR_HOME}"
      notif_theme="${notif_theme/\$\{WAYBAR_HOME\}/$WAYBAR_HOME}"
      notif_width=$(waybar_settings_get '.rofi.notifications.width' '650')

      if [ -n "$notif_theme" ] && [ -f "$notif_theme" ]; then
        sel="$(printf '%s' "$history" | jq -r '.[] | "\(.id)\t\(.summary // "Notification")"' \
          | rofi -dmenu -i -p "Notifications" -no-fixed-num-lines -theme "$notif_theme" -theme-str "window { width: ${notif_width}px; }" 2>/dev/null || true)"
      else
        sel="$(printf '%s' "$history" | jq -r '.[] | "\(.id)\t\(.summary // "Notification")"' \
          | rofi -dmenu -i -p "Notifications" -no-fixed-num-lines -theme-str "window { width: ${notif_width}px; }" 2>/dev/null || true)"
      fi
      if [ -n "$sel" ]; then
        id="${sel%%	*}"
        makoctl invoke -n "$id" 2>/dev/null || true
      fi
      return 0
    fi
    makoctl restore 2>/dev/null || true
    notify-send "Notifications" "Install SwayNC or rofi for a notification center UI" 2>/dev/null || true
    return 0
  fi

  notify-send "Notifications" "No Hyprland notification UI found (install swaync)" 2>/dev/null || true
}

hyprland_toggle_dnd() {
  if command -v swaync-client >/dev/null 2>&1; then
    swaync-client -d -sw
    signal_refresh
    return 0
  fi

  if command -v makoctl >/dev/null 2>&1; then
    makoctl mode -t do-not-disturb >/dev/null 2>&1 || true
    signal_refresh
    return 0
  fi
}

case "$compositor" in
  hyprland)
    case "$action" in
      open) hyprland_open ;;
      dnd | toggle-dnd) hyprland_toggle_dnd ;;
      settings)
        if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/swaync/config.json" ]; then
          notify-send "Notifications" "Edit ~/.config/swaync/config.json (no GUI settings on Hyprland)" 2>/dev/null || true
        elif [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/mako/config" ]; then
          notify-send "Notifications" "Edit ~/.config/mako/config (no GUI settings on Hyprland)" 2>/dev/null || true
        else
          notify-send "Notifications" "Configure swaync/mako in ~/.config (no GUI settings on Hyprland)" 2>/dev/null || true
        fi
        ;;
      *) hyprland_open ;;
    esac
    ;;
  kde)
    case "$action" in
      open) kde_open_notifications ;;
      dnd | toggle-dnd)
        kde_toggle_dnd
        signal_refresh
        ;;
      settings) kde_open_settings ;;
      *) kde_open_notifications ;;
    esac
    ;;
  *)
    case "$action" in
      dnd | toggle-dnd)
        if command -v dunstctl >/dev/null 2>&1; then
          dunstctl set-paused toggle
          signal_refresh
        fi
        ;;
      *)
        if command -v dunstctl >/dev/null 2>&1; then
          dunstctl set-paused toggle
          signal_refresh
        else
          notify-send "Notifications" "No supported notification daemon found" 2>/dev/null || true
        fi
        ;;
    esac
    ;;
esac
