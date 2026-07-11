#!/usr/bin/env bash
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
if [ -f "$WAYBAR_SCRIPTS/lib/waybar-settings.sh" ]; then
  . "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
else
  . "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
fi

config_override=$(waybar_settings_get '.hypr_tools.keybinds_config' '')
if [ -n "$config_override" ] && [ "$config_override" != "null" ]; then
  config="$config_override"
else
  config="${HYPRLAND_CONFIG:-$HOME/.config/hypr/hyprland.conf}"
fi
terminal_app=$(waybar_settings_get '.apps.terminal' 'ghostty')
rofi_theme_configured=$(waybar_settings_get '.rofi.theme' '')
rofi_theme_configured="${rofi_theme_configured/\$WAYBAR_HOME/$WAYBAR_HOME}"
rofi_theme_configured="${rofi_theme_configured/\$\{WAYBAR_HOME\}/$WAYBAR_HOME}"
rofi_theme="${rofi_theme_configured:-${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/theme/rofi/dock-rofi.rasi}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/keybindhint.txt"

"$WAYBAR_SCRIPTS/lib/compositor-gate.sh" --show hyprland -- true >/dev/null 2>&1 || exit 0

mkdir -p "$cache_dir"

tmp_file="$cache_file.tmp.$$"
if command -v hyprkeys >/dev/null 2>&1; then
  hyprkeys -b -c "$config" >"$tmp_file" 2>/dev/null || true
elif command -v hyprctl >/dev/null 2>&1; then
  hyprctl binds >"$tmp_file" 2>/dev/null || true
else
  notify-send "Keybinds" "hyprkeys/hyprctl not available" 2>/dev/null || true
  exit 1
fi

if [ -s "$tmp_file" ]; then
  mv -f "$tmp_file" "$cache_file"
else
  rm -f "$tmp_file"
fi

[ -s "$cache_file" ] || exit 0

if command -v rofi >/dev/null 2>&1; then
  rofi_args=(-dmenu -i -p "Keybinds")
  [ -f "$rofi_theme" ] && rofi_args+=(-theme "$rofi_theme")
  rofi "${rofi_args[@]}" <"$cache_file" >/dev/null || true
  exit 0
fi

if command -v wofi >/dev/null 2>&1; then
  wofi --dmenu --prompt "Keybinds" <"$cache_file" >/dev/null || true
  exit 0
fi

"$WAYBAR_SCRIPTS/tools/app-open.sh" "$terminal_app" -e less "$cache_file"
