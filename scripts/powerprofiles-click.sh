#!/usr/bin/env sh
set -eu

target="${1:-next}"

if ! command -v powerprofilesctl >/dev/null 2>&1; then
  exit 0
fi

current=$(powerprofilesctl get 2>/dev/null || true)
[ -z "$current" ] && exit 0

case "$target" in
  menu)
    if command -v rofi >/dev/null 2>&1; then
      profiles="⚡ performance\n⚖️ balanced\n🔋 power-saver"
      selected=$(printf "%b" "$profiles" | rofi -dmenu -i -p "Power Profile" -theme-str 'window {width: 250px; lines: 3;}')
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
  balanced|performance|power-saver)
    ;;
  *)
    exit 1
    ;;
esac

powerprofilesctl set "$target" >/dev/null 2>&1 || exit 0
notify-send "Power profile" "Switched to $target" 2>/dev/null || true

script_dir="${0%/*}"
# shellcheck source=waybar-signal.sh
if [ -f "$script_dir/waybar-signal.sh" ]; then
  "$script_dir/waybar-signal.sh" 3
else
  pkill -x -RTMIN+3 waybar >/dev/null 2>&1 || true
fi