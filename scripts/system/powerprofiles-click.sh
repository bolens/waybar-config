#!/usr/bin/env bash
# Cycle power-profiles-daemon profiles (next/prev/menu) and signal Waybar.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

target="${1:-next}"
script_dir="${0%/*}"
if [ -f "$WAYBAR_SCRIPTS/lib/waybar-settings.sh" ]; then
  # shellcheck source=../lib/waybar-settings.sh
  . "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
fi

if ! command -v powerprofilesctl >/dev/null 2>&1; then
  exit 0
fi

current=$(powerprofilesctl get 2>/dev/null || true)
[ -z "$current" ] && exit 0

case "$target" in
  menu)
    if command -v rofi >/dev/null 2>&1; then
      pp_width=$(waybar_settings_get '.rofi.powerprofiles.width' '250')
      pp_lines=$(waybar_settings_get '.rofi.powerprofiles.lines' '3')
      profiles="⚡ performance\n⚖️ balanced\n🔋 power-saver"
      selected=$(printf "%b" "$profiles" | rofi -dmenu -i -p "Power Profile" -theme-str "window {width: ${pp_width}px; lines: ${pp_lines};}")
      if [ -n "$selected" ]; then
        target=$(printf "%s" "$selected" | awk '{print $NF}')
      else
        exit 0
      fi
    else
      case "$current" in
        performance) target="balanced" ;;
        balanced) target="power-saver" ;;
        *) target="performance" ;;
      esac
    fi
    ;;
  next)
    case "$current" in
      performance) target="balanced" ;;
      balanced) target="power-saver" ;;
      *) target="performance" ;;
    esac
    ;;
  balanced | performance | power-saver)
    ;;
  *)
    exit 1
    ;;
esac

powerprofilesctl set "$target" >/dev/null 2>&1 || exit 0
notify-send "Power profile" "Switched to $target" 2>/dev/null || true

# shellcheck source=waybar-signal.sh
"$WAYBAR_SCRIPTS/lib/waybar-signal.sh" powerprofiles
