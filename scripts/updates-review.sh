#!/usr/bin/env sh
set -eu

# 1. Gather repository updates
repos=""
if command -v checkupdates >/dev/null 2>&1; then
  repos=$(checkupdates 2>/dev/null || true)
fi

# 2. Gather AUR updates
aur=""
if command -v paru >/dev/null 2>&1; then
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

choice=$(printf "%b" "$menu_options" | rofi -dmenu -i -p "System Updates" -theme-str 'window {width: 650px; height: 500px;}')

if [ "$choice" = "🚀 Upgrade System Now" ]; then
  script_dir="${0%/*}"
  # shellcheck source=compositor-session.sh
  if [ -f "$script_dir/compositor-session.sh" ]; then
    . "$script_dir/compositor-session.sh"
  else
    # shellcheck source=compositor-session.sh
    . "$HOME/.config/waybar/scripts/compositor-session.sh"
  fi
  
  comp=$(detect_compositor)
  if term=$(_pick_terminal "$comp"); then
    _run_in_terminal "$term" paru -Syu
  else
    # Fallback to ghostty or generic
    ghostty -e paru -Syu &
  fi
fi