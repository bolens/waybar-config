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
apt_update=$(waybar_settings_get '.apps.apt_update' '')
dnf_update=$(waybar_settings_get '.apps.dnf_update' '')
terminal_app=$(waybar_settings_get '.apps.terminal' 'ghostty')

# Same backend order as updates-status.sh (checkupdates → apt → dnf).
detect_updates_backend() {
  if [ -n "${WAYBAR_UPDATES_BACKEND:-}" ]; then
    printf '%s' "$WAYBAR_UPDATES_BACKEND"
    return 0
  fi
  if command -v checkupdates >/dev/null 2>&1; then
    printf 'arch'
  elif command -v apt >/dev/null 2>&1; then
    printf 'apt'
  elif command -v dnf >/dev/null 2>&1; then
    printf 'dnf'
  else
    printf 'none'
  fi
}

backend=$(detect_updates_backend)

# 1. Gather repository updates
repos=""
case "$backend" in
  arch)
    if command -v checkupdates >/dev/null 2>&1; then
      repos=$(checkupdates 2>/dev/null || true)
    fi
    ;;
  apt)
    repos=$(apt list --upgradable 2>/dev/null | grep -E '/[a-z].*upgradable' || true)
    ;;
  dnf)
    repos=$(dnf check-upgrade -q 2>/dev/null | awk 'NF && $1 !~ /^Obsoleting/ && $1 !~ /^Last/' || true)
    ;;
esac

# 2. Gather AUR updates (Arch only, when enabled)
aur=""
if [ "$backend" = "arch" ] && [ "$enable_aur" = "true" ] && command -v paru >/dev/null 2>&1; then
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
  # Prefer settings click targets (apps.paru_update / apt_update / dnf_update).
  # Never hard-require paru: Arch falls back to `sudo pacman -Syu` when paru is missing.
  case "$backend" in
    arch)
      if [ -n "$paru_update" ]; then
        # shellcheck disable=SC2086
        "$WAYBAR_SCRIPTS/tools/app-open.sh" $paru_update
        exit 0
      fi
      ;;
    apt)
      if [ -n "$apt_update" ]; then
        # shellcheck disable=SC2086
        "$WAYBAR_SCRIPTS/tools/app-open.sh" $apt_update
        exit 0
      fi
      ;;
    dnf)
      if [ -n "$dnf_update" ]; then
        # shellcheck disable=SC2086
        "$WAYBAR_SCRIPTS/tools/app-open.sh" $dnf_update
        exit 0
      fi
      ;;
  esac

  # shellcheck source=compositor-session.sh
  . "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

  comp=$(detect_compositor)
  case "$backend" in
    arch)
      upgrade_cmd=(paru -Syu)
      if ! command -v paru >/dev/null 2>&1; then
        upgrade_cmd=(sudo pacman -Syu)
      fi
      ;;
    apt)
      upgrade_cmd=(sudo apt upgrade)
      ;;
    dnf)
      upgrade_cmd=(sudo dnf upgrade)
      ;;
    *)
      notify-send "System Updates" "No known package manager upgrade command" 2>/dev/null || true
      exit 0
      ;;
  esac

  if term=$(_pick_terminal "$comp"); then
    _run_in_terminal "$term" "${upgrade_cmd[@]}"
  else
    "$WAYBAR_SCRIPTS/tools/app-open.sh" "$terminal_app" -e "${upgrade_cmd[@]}"
  fi
fi
