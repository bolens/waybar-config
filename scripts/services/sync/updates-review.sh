#!/usr/bin/env bash
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
if [ -f "$WAYBAR_SCRIPTS/lib/waybar-settings.sh" ]; then
  # shellcheck disable=SC1091
  . "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
fi

rofi_width=$(waybar_settings_get '.rofi.updates.width' '650')
rofi_height=$(waybar_settings_get '.rofi.updates.height' '500')
enable_aur=$(waybar_settings_get '.updates.enable_aur' 'false')
if [ "${WAYBAR_UPDATES_ENABLE_AUR:-}" = "1" ]; then
  enable_aur=true
elif [ "${WAYBAR_UPDATES_ENABLE_AUR:-}" = "0" ]; then
  enable_aur=false
fi
paru_update=$(waybar_settings_get '.apps.paru_update' '')
terminal_app=$(waybar_settings_get '.apps.terminal' 'ghostty')

# 1. Gather repository updates
repos=""
if command -v checkupdates >/dev/null 2>&1; then
  repos=$(checkupdates 2>/dev/null || true)
fi

# 2. Gather AUR updates (when enabled)
aur=""
if [ "$enable_aur" = "true" ] && command -v paru >/dev/null 2>&1; then
  aur=$(paru -Qua 2>/dev/null || true)
fi

# 3. Gather Flatpak updates
flatpaks=""
if command -v flatpak >/dev/null 2>&1; then
  flatpaks=$(flatpak remote-ls --updates --columns=application,version 2>/dev/null || true)
fi

# Format items for rofi
list_items=""
if [ -n "$repos" ]; then
  list_items="${list_items}=== Repository Updates ===\n$repos\n\n"
fi
if [ -n "$aur" ]; then
  list_items="${list_items}=== AUR Updates ===\n$aur\n\n"
fi
if [ -n "$flatpaks" ]; then
  list_items="${list_items}=== Flatpak Updates ===\n$flatpaks\n\n"
fi

if [ -z "$list_items" ]; then
  notify-send "System Updates" "Your system is up to date!" 2>/dev/null || true
  exit 0
fi

# We add options to the list:
# "Upgrade System Now" or just viewing them.
menu_options="🚀 Upgrade System Now\n❌ Close\n\n=== Pending Updates ===\n$list_items"

choice=$(printf "%b" "$menu_options" | rofi -dmenu -i -p "System Updates" -theme-str "window {width: ${rofi_width}px; height: ${rofi_height}px;}")

if [ "$choice" = "🚀 Upgrade System Now" ]; then
  if [ -n "$paru_update" ]; then
    # shellcheck disable=SC2086
    "$WAYBAR_SCRIPTS/tools/app-open.sh" $paru_update
    exit 0
  fi

  # shellcheck source=compositor-session.sh
  if [ -f "$WAYBAR_SCRIPTS/lib/compositor-session.sh" ]; then
    . "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
  else
    # shellcheck source=compositor-session.sh
    . "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
  fi

  comp=$(detect_compositor)
  if term=$(_pick_terminal "$comp"); then
    _run_in_terminal "$term" paru -Syu
  else
    "$WAYBAR_SCRIPTS/tools/app-open.sh" "$terminal_app" -e paru -Syu
  fi
fi
