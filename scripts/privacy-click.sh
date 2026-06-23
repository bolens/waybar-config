#!/usr/bin/env bash
# Privacy indicator clicks (screenshare, webcam, mic, speaker).
set -euo pipefail

kind="${1:-}"
action="${2:-click}"
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/privacy-status.json"

notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send "$1" "$2" || true
}

refresh_privacy() {
  pkill -x -RTMIN+17 waybar >/dev/null 2>&1 || true
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
  "$script_dir/app-open.sh" systemsettings6 kcm_app-permissions
}

open_camera_settings() {
  if command -v systemsettings6 >/dev/null 2>&1; then
    "$script_dir/app-open.sh" systemsettings6 kcm_kamera
    return
  fi
  open_app_permissions
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
        "$script_dir/mic-toggle.sh"
        ;;
      middle)
        wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
        refresh_privacy
        ;;
      right)
        "$script_dir/audio-click.sh" manage
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  audio-out)
    case "$action" in
      click)
        "$script_dir/audio-click.sh" manage
        ;;
      middle)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        refresh_privacy
        ;;
      right)
        "$script_dir/app-open.sh" goxlr-launcher
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
