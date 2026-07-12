#!/usr/bin/env bash
# Privacy indicator clicks (screenshare, webcam, mic, speaker).
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

kind="${1:-}"
action="${2:-click}"
script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/privacy-status.json"
if [ -f "$WAYBAR_SCRIPTS/lib/waybar-settings.sh" ]; then
  # shellcheck source=../../lib/waybar-settings.sh
  . "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
fi
# shellcheck source=../../lib/app-open-lib.sh
. "$WAYBAR_SCRIPTS/lib/app-open-lib.sh"
# shellcheck source=../../lib/compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send "$1" "$2" || true
}

open_settings_app() {
  local cmd="$1"
  waybar_app_open "$cmd"
}

refresh_privacy() {
  "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" privacy
  if [ -x "$script_dir/privacy-status.sh" ]; then
    local tmp_cache="$cache_file.tmp.$$"
    "$script_dir/privacy-status.sh" --refresh >"$tmp_cache" 2>/dev/null || true
    if [ -s "$tmp_cache" ]; then
      mv -f "$tmp_cache" "$cache_file"
    else
      rm -f "$tmp_cache"
    fi
  fi
}

read_privacy() {
  local key="$1"
  jq -r --arg key "$key" '.[$key] // {active:false,apps:[]}' "$cache_file" 2>/dev/null \
    || printf '{"active":false,"apps":[]}'
}

apps_for() {
  read_privacy "$1" | jq -r '.apps | join(", ")'
}

is_active() {
  read_privacy "$1" | jq -r '.active'
}

open_app_permissions() {
  local comp settings hypr_override
  comp="$(detect_compositor)"
  settings="$(waybar_settings_get '.apps.privacy_settings' 'systemsettings6 kcm_app-permissions')"
  case "$comp" in
    kde)
      open_settings_app "$settings"
      ;;
    *)
      hypr_override="$(waybar_settings_get '.apps.privacy_settings_hyprland' '')"
      if [ -n "$hypr_override" ]; then
        open_settings_app "$hypr_override"
        return
      fi
      # Honor explicit non-Plasma overrides (tests / custom tooling).
      case "$settings" in
        systemsettings* | kcm_*)
          refresh_privacy
          status_notify "Privacy" screenshare
          notify "Privacy" "On Hyprland, revoke sharing from the portal prompt or close the sharing app"
          ;;
        *)
          open_settings_app "$settings"
          ;;
      esac
      ;;
  esac
}

open_camera_settings() {
  local comp cam hypr_override
  comp="$(detect_compositor)"
  cam="$(waybar_settings_get '.apps.camera_settings' 'systemsettings6 kcm_kamera')"
  case "$comp" in
    kde)
      if [ -n "$cam" ]; then
        open_settings_app "$cam"
        return
      fi
      open_app_permissions
      ;;
    *)
      hypr_override="$(waybar_settings_get '.apps.camera_settings_hyprland' '')"
      if [ -n "$hypr_override" ]; then
        open_settings_app "$hypr_override"
        return
      fi
      case "$cam" in
        systemsettings* | kcm_*)
          refresh_privacy
          status_notify "Webcam" webcam
          ;;
        *)
          open_settings_app "$cam"
          ;;
      esac
      ;;
  esac
}

status_notify() {
  local title="$1"
  local key="$2"
  local apps
  apps="$(apps_for "$key")"
  if [ "$(is_active "$key")" = "true" ] && [ -n "$apps" ]; then
    notify "$title in use" "$apps"
  else
    notify "$title" "Nothing is using this right now"
  fi
}

case "$kind" in
  screenshare)
    case "$action" in
      click)
        refresh_privacy
        status_notify "Screen share" screenshare
        ;;
      middle)
        refresh_privacy
        ;;
      right)
        open_app_permissions
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  webcam)
    case "$action" in
      click)
        refresh_privacy
        status_notify "Webcam" webcam
        ;;
      middle)
        refresh_privacy
        ;;
      right)
        open_camera_settings
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  audio-in)
    case "$action" in
      click)
        "$WAYBAR_SCRIPTS/media/mic-toggle.sh"
        ;;
      middle)
        wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
        refresh_privacy
        ;;
      right)
        "$WAYBAR_SCRIPTS/media/audio-click.sh" manage
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  audio-out)
    case "$action" in
      click)
        "$WAYBAR_SCRIPTS/media/audio-click.sh" manage
        ;;
      middle)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        refresh_privacy
        ;;
      right)
        "$WAYBAR_SCRIPTS/tools/app-open.sh" goxlr-launcher
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  location)
    case "$action" in
      click)
        refresh_privacy
        status_notify "Location" location
        ;;
      middle)
        refresh_privacy
        ;;
      right)
        open_app_permissions
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  *)
    printf 'Usage: %s screenshare|webcam|audio-in|audio-out|location [click|middle|right]\n' "$0" >&2
    exit 1
    ;;
esac
