#!/usr/bin/env sh
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

compositor="$(detect_compositor)"
action="${1:-}"

confirm_action() {
  local action_name="$1"
  if command -v rofi >/dev/null 2>&1; then
    local theme='
      window {
        width: 380px;
        location: center;
        anchor: center;
        border: 2px;
        border-color: #ff2a7f;
        border-radius: 8px;
        background-color: #090b12f2;
        padding: 15px;
      }
      mainbox {
        spacing: 12px;
        children: [ message, listview ];
        background-color: transparent;
      }
      message {
        padding: 5px;
        background-color: transparent;
        text-color: #c8f6ff;
      }
      listview {
        lines: 2;
        columns: 1;
        fixed-height: true;
        background-color: transparent;
      }
      element {
        padding: 8px 12px;
        border-radius: 4px;
        background-color: #0d111c;
        text-color: #d6f7ff;
      }
      element selected {
        background-color: #ff2a7f;
        text-color: #ffffff;
      }
      element-text {
        font: "JetBrainsMono Nerd Font 12";
        background-color: transparent;
        text-color: inherit;
        horizontal-align: 0.5;
      }
    '
    local choice
    choice=$(printf "No, cancel\nYes, %s" "$action_name" | rofi -dmenu -i -markup -theme-str "$theme" -p "Confirm" -mesg "<span font='13'>Are you sure you want to <b>$action_name</b>?</span>")
    if [ "$choice" = "Yes, $action_name" ]; then
      return 0
    fi
    return 1
  fi
  return 0
}

case "$action" in
  lock)
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
    ;;
  logout)
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
    echo "Usage: $0 {lock|logout|suspend|reboot|shutdown}" >&2
    exit 1
    ;;
esac
