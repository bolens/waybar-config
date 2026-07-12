#!/usr/bin/env bash
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
# shellcheck source=waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck source=rofi-popup-lib.sh
. "$WAYBAR_SCRIPTS/lib/rofi-popup-lib.sh"

compositor="$(detect_compositor)"
action="${1:-}"

confirm_action() {
  local action_name="$1"
  if command -v rofi >/dev/null 2>&1; then
    local theme choice
    ROFI_THEME_WIDTH=380 ROFI_THEME_LINES=2 ROFI_THEME_COLUMNS=1 \
      ROFI_THEME_RADIUS=8 ROFI_THEME_PADDING=15 ROFI_THEME_ELEMENT_PAD="8px 12px" \
      ROFI_THEME_FONT_SIZE=12 ROFI_THEME_BORDER=critical \
      theme="$(rofi_theme_str_from_settings)"
    choice=$(printf "No, cancel\nYes, %s" "$action_name" | rofi -dmenu -i -markup -theme-str "$theme" -p "Confirm" -mesg "<span font='13'>Are you sure you want to <b>$action_name</b>?</span>")
    if [ "$choice" = "Yes, $action_name" ]; then
      return 0
    fi
    return 1
  fi
  return 0
}

do_lock() {
  case "$compositor" in
    hyprland)
      if command -v hyprlock >/dev/null 2>&1; then
        hyprlock
      elif command -v swaylock >/dev/null 2>&1; then
        swaylock -f
      else
        loginctl lock-session
      fi
      ;;
    kde)
      loginctl lock-session
      ;;
    *)
      loginctl lock-session || swaylock -f || hyprlock
      ;;
  esac
}

do_logout() {
  confirm_action "logout" || exit 0
  case "$compositor" in
    hyprland)
      if command -v hyprctl >/dev/null 2>&1; then
        hyprctl dispatch exit || loginctl terminate-session "${XDG_SESSION_ID:-}"
      else
        loginctl terminate-session "${XDG_SESSION_ID:-}"
      fi
      ;;
    kde)
      if command -v qdbus6 >/dev/null 2>&1; then
        qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout || loginctl terminate-session "${XDG_SESSION_ID:-}"
      elif command -v qdbus >/dev/null 2>&1; then
        qdbus org.kde.Shutdown /Shutdown org.kde.Shutdown.logout || loginctl terminate-session "${XDG_SESSION_ID:-}"
      else
        loginctl terminate-session "${XDG_SESSION_ID:-}"
      fi
      ;;
    *)
      loginctl terminate-session "${XDG_SESSION_ID:-}"
      ;;
  esac
}

show_power_menu() {
  if ! command -v rofi >/dev/null 2>&1; then
    notify-send "Power" "rofi is required for the power menu" 2>/dev/null || true
    exit 1
  fi

  # wlogout-style grid: icon + label per cell
  local theme choice
  ROFI_THEME_WIDTH=520 ROFI_THEME_LINES=1 ROFI_THEME_COLUMNS=5 \
    ROFI_THEME_RADIUS=12 ROFI_THEME_PADDING=18 ROFI_THEME_ELEMENT_PAD="16px 10px" \
    ROFI_THEME_ORIENTATION=vertical ROFI_THEME_FONT_SIZE=14 ROFI_THEME_BORDER=critical \
    theme="$(rofi_theme_str_from_settings)"
  # listview spacing for the 5-column grid (helper keeps layout structure; add spacing)
  theme="${theme}
listview {
  spacing: 10px;
}
element {
  border-radius: 8px;
}
element-text {
  vertical-align: 0.5;
}
"
  choice=$(
    printf '%s\n' \
      "  Lock" \
      "󰍃  Logout" \
      "󰤄  Suspend" \
      "󰜉  Reboot" \
      "󰐥  Shutdown" \
      | rofi -dmenu -i -markup -theme-str "$theme" -p "Power" \
        -mesg "<span font='13'>Session controls</span>"
  ) || exit 0

  case "$choice" in
    *"Lock"*) do_lock ;;
    *"Logout"*) do_logout ;;
    *"Suspend"*)
      confirm_action "suspend" || exit 0
      systemctl suspend
      ;;
    *"Reboot"*)
      confirm_action "reboot" || exit 0
      systemctl reboot
      ;;
    *"Shutdown"*)
      confirm_action "shutdown" || exit 0
      systemctl poweroff
      ;;
  esac
}

case "$action" in
  menu)
    show_power_menu
    ;;
  lock)
    do_lock
    ;;
  logout)
    do_logout
    ;;
  suspend)
    confirm_action "suspend" || exit 0
    systemctl suspend
    ;;
  reboot)
    confirm_action "reboot" || exit 0
    systemctl reboot
    ;;
  shutdown)
    confirm_action "shutdown" || exit 0
    systemctl poweroff
    ;;
  *)
    echo "Usage: $0 {menu|lock|logout|suspend|reboot|shutdown}" >&2
    exit 1
    ;;
esac
