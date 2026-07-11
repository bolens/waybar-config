#!/usr/bin/env bash
# Resolve data/waybar-settings.jsonc apps.* keys with compositor-aware overrides.
# Usage: app-open-key.sh <apps_key>
#
# Resolution order:
#   1. .apps.<key>_hyprland when compositor is hyprland (if non-empty)
#   2. Built-in remaps for Plasma-only keys on Hyprland
#   3. .apps.<key>
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

key="${1:-}"
if [ -z "$key" ]; then
  printf 'Usage: %s <apps_key>\n' "${0##*/}" >&2
  exit 1
fi

# shellcheck source=../lib/compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
# shellcheck source=../lib/waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck source=../lib/app-open-lib.sh
. "$WAYBAR_SCRIPTS/lib/app-open-lib.sh"

comp="$(detect_compositor)"
cmd=""

if [ "$comp" = "hyprland" ]; then
  cmd="$(waybar_settings_get ".apps.${key}_hyprland" "")"
fi

if [ -z "$cmd" ] || [ "$cmd" = "null" ]; then
  if [ "$comp" = "hyprland" ]; then
    case "$key" in
      plasma_system_monitor)
        key="system_monitor"
        ;;
      power_settings)
        # Prefer missioncenter / powerprofiles UI over Plasma systemsettings.
        key="system_monitor"
        ;;
      input_settings)
        solaar_cmd="$(waybar_settings_get '.apps.solaar' 'solaar')"
        solaar_bin="${solaar_cmd%% *}"
        if command -v "$solaar_bin" >/dev/null 2>&1; then
          waybar_app_open_exec "$solaar_cmd"
        fi
        notify-send "Input" "Set .apps.input_settings_hyprland or install solaar" 2>/dev/null || true
        exit 0
        ;;
      clock)
        if command -v gnome-clocks >/dev/null 2>&1; then
          exec "$WAYBAR_SCRIPTS/tools/app-open.sh" gnome-clocks
        fi
        if command -v clock >/dev/null 2>&1; then
          exec "$WAYBAR_SCRIPTS/tools/app-open.sh" clock
        fi
        notify-send "Clock" "No Hyprland clock app found (.apps.clock_hyprland)" 2>/dev/null || true
        exit 0
        ;;
    esac
  fi
  cmd="$(waybar_settings_get ".apps.${key}" "")"
fi

if [ -z "$cmd" ] || [ "$cmd" = "null" ]; then
  notify-send "Waybar" "No app configured for apps.${key}" 2>/dev/null || true
  exit 1
fi

waybar_app_open_exec "$cmd"
