#!/usr/bin/env sh
# Cycle keyboard layout (next|prev). Used by custom/keyboard-layout clicks.
set -eu

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
. "$script_dir/compositor-session.sh"

direction="${1:-next}"
comp="$(detect_compositor)"
WAYBAR_HOME="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
settings="$WAYBAR_HOME/data/waybar-settings.json"

cycle_plasma() {
  method="org.kde.KeyboardLayouts.switchToNextLayout"
  if [ "$direction" = "prev" ]; then
    method="org.kde.KeyboardLayouts.switchToPreviousLayout"
  fi
  if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.keyboard /Layouts "$method" >/dev/null 2>&1 || true
    return
  fi
  if command -v qdbus >/dev/null 2>&1; then
    qdbus org.kde.keyboard /Layouts "$method" >/dev/null 2>&1 || true
    return
  fi
  dbus-send --session --type=method_call \
    --dest=org.kde.keyboard /Layouts "$method" >/dev/null 2>&1 || true
}

cycle_hyprland() {
  if ! command -v hyprctl >/dev/null 2>&1; then
    return 0
  fi
  kb="$(hyprctl devices -j 2>/dev/null | jq -r '.keyboards[0].name // empty')"
  [ -n "$kb" ] || return 0
  if [ "$direction" = "prev" ]; then
    hyprctl switchxkblayout "$kb" prev >/dev/null 2>&1 || true
  else
    hyprctl switchxkblayout "$kb" next >/dev/null 2>&1 || true
  fi
}

case "$comp" in
  kde) cycle_plasma ;;
  hyprland) cycle_hyprland ;;
esac

sig=2
if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
  sig="$(jq -r '.signals.keyboard_layout // 2' "$settings")"
fi
"$script_dir/waybar-signal.sh" "$sig" >/dev/null 2>&1 || true
