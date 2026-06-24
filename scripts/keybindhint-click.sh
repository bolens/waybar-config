#!/usr/bin/env sh
set -eu

script_dir="${0%/*}"
if [ -f "$script_dir/waybar-settings.sh" ]; then
  . "$script_dir/waybar-settings.sh"
else
  . "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-settings.sh"
fi

config="${HYPRLAND_CONFIG:-$HOME/.config/hypr/hyprland.conf}"
rofi_theme_configured=$(waybar_settings_get '.rofi.theme' '')
rofi_theme_configured="${rofi_theme_configured/\$WAYBAR_HOME/$WAYBAR_HOME}"
rofi_theme_configured="${rofi_theme_configured/\$\{WAYBAR_HOME\}/$WAYBAR_HOME}"
rofi_theme="${rofi_theme_configured:-${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/themes/dock-rofi.rasi}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/keybindhint.txt"

"$script_dir/compositor-gate.sh" --show hyprland -- true >/dev/null 2>&1 || exit 0

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

"$script_dir/app-open.sh" ghostty -e less "$cache_file"
