#!/usr/bin/env sh
set -eu

mode="${1:-toggle}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
force_state_file="$cache_dir/nightlight-kde-force"

mkdir -p "$cache_dir"

# shellcheck source=compositor-session.sh
. "${0%/*}/compositor-session.sh"
. "${0%/*}/waybar-settings.sh"

temp_setting=$(waybar_settings_get '.nightlight.temperature' '')
temp="${temp_setting:-${HYPRSUNSET_TEMP:-4200}}"

get_backend() {
  comp="$(detect_compositor)"
  if [ "$comp" = "kde" ]; then
    printf 'kde\n'
  else
    printf 'hypr\n'
  fi
}

qdbus_cmd() {
  if command -v qdbus6 >/dev/null 2>&1; then
    timeout 2 qdbus6 "$@"
  else
    timeout 2 qdbus "$@"
  fi
}

start_nightlight() {
  if ! command -v hyprsunset >/dev/null 2>&1; then
    return 1
  fi

  hyprsunset -t "$temp" >/dev/null 2>&1 &
  pid=$!

  # hyprsunset can exit immediately on unsupported compositors.
  sleep 0.25
  if kill -0 "$pid" >/dev/null 2>&1 || pgrep -x hyprsunset >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

refresh_waybar() {
  rm -f "$cache_dir/nightlight-status.json" 2>/dev/null || true
  pkill -x -RTMIN+14 waybar >/dev/null 2>&1 || true
}

kde_get_enabled() {
  qdbus_cmd org.kde.KWin /org/kde/KWin/NightLight org.kde.KWin.NightLight.enabled 2>/dev/null || printf 'false\n'
}

kde_get_inhibited() {
  qdbus_cmd org.kde.KWin /org/kde/KWin/NightLight org.kde.KWin.NightLight.inhibited 2>/dev/null || printf 'false\n'
}

# kde_toggle:
# Triggers the virtual "Toggle Night Color" shortcut in KWin.
# KDE global shortcuts are controlled by kglobalaccel, which broadcasts window manager commands.
kde_toggle() {
  qdbus_cmd org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Toggle Night Color" >/dev/null 2>&1
}

# kde_reconfigure:
# Commands KWin to reload its entire configuration properties immediately over DBus.
kde_reconfigure() {
  qdbus_cmd org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
}

kde_preview_start() {
  qdbus_cmd org.kde.KWin /org/kde/KWin/NightLight org.kde.KWin.NightLight.preview "$temp" >/dev/null 2>&1
}

kde_preview_stop() {
  qdbus_cmd org.kde.KWin /org/kde/KWin/NightLight org.kde.KWin.NightLight.stopPreview >/dev/null 2>&1
}

open_kde_nightcolor_settings() {
  if command -v systemsettings6 >/dev/null 2>&1; then
    systemsettings6 kcm_nightlight >/dev/null 2>&1 &
    return 0
  fi
  if command -v systemsettings >/dev/null 2>&1; then
    systemsettings kcm_nightlight >/dev/null 2>&1 &
    return 0
  fi
  if command -v kcmshell6 >/dev/null 2>&1; then
    kcmshell6 kcm_nightlight >/dev/null 2>&1 &
    return 0
  fi
  if command -v kcmshell5 >/dev/null 2>&1; then
    kcmshell5 kcm_nightcolor >/dev/null 2>&1 &
    return 0
  fi
  return 1
}

backend=$(get_backend)

case "$mode" in
  toggle)
    case "$backend" in
      kde)
        if kde_toggle; then
          sleep 0.2
          if [ "$(kde_get_inhibited)" = "true" ]; then
            notify-send "Night light" "Disabled (KDE backend)" 2>/dev/null || true
          elif [ "$(kde_get_enabled)" = "true" ]; then
            notify-send "Night light" "Enabled (KDE backend)" 2>/dev/null || true
          else
            notify-send "Night light" "Toggled (KDE backend)" 2>/dev/null || true
          fi
        else
          notify-send "Night light" "Failed to toggle KDE Night Color" 2>/dev/null || true
        fi
        ;;
      *)
        if pgrep -x hyprsunset >/dev/null 2>&1; then
          pkill -x hyprsunset >/dev/null 2>&1 || true
          notify-send "Night light" "Disabled" 2>/dev/null || true
        else
          if start_nightlight; then
            notify-send "Night light" "Enabled at ${temp}K" 2>/dev/null || true
          else
            notify-send "Night light" "Failed to enable (hyprsunset backend unavailable or unsupported compositor)" 2>/dev/null || true
          fi
        fi
        ;;
    esac
    refresh_waybar
    ;;
  restart)
    case "$backend" in
      kde)
        kde_reconfigure
        notify-send "Night light" "KDE Night Color reloaded" 2>/dev/null || true
        ;;
      *)
        pkill -x hyprsunset >/dev/null 2>&1 || true
        if start_nightlight; then
          notify-send "Night light" "Restarted at ${temp}K" 2>/dev/null || true
        else
          notify-send "Night light" "Failed to restart (hyprsunset backend unavailable or unsupported compositor)" 2>/dev/null || true
        fi
        ;;
    esac
    refresh_waybar
    ;;
  force_toggle)
    case "$backend" in
      kde)
        if [ -f "$force_state_file" ]; then
          # Stop the temp color temperature preview on KWin
          if kde_preview_stop; then
            rm -f "$force_state_file"
            notify-send "Night light" "Force off (KDE backend)" 2>/dev/null || true
          else
            notify-send "Night light" "Failed to force off KDE Night Color" 2>/dev/null || true
          fi
        else
          # Start temp color temperature preview on KWin.
          # KWin's preview method forces color correction to a custom temperature without
          # changing the permanent system settings configuration.
          if kde_preview_start; then
            tmp_force="$force_state_file.tmp.$$"
            printf '%s\n' "$temp" > "$tmp_force"
            mv -f "$tmp_force" "$force_state_file"
            notify-send "Night light" "Force on at ${temp}K (KDE backend)" 2>/dev/null || true
          else
            notify-send "Night light" "Failed to force on KDE Night Color" 2>/dev/null || true
          fi
        fi
        ;;
      *)
        if pgrep -x hyprsunset >/dev/null 2>&1; then
          pkill -x hyprsunset >/dev/null 2>&1 || true
          notify-send "Night light" "Force off" 2>/dev/null || true
        else
          if start_nightlight; then
            notify-send "Night light" "Force on at ${temp}K" 2>/dev/null || true
          else
            notify-send "Night light" "Failed to force on" 2>/dev/null || true
          fi
        fi
        ;;
    esac
    refresh_waybar
    ;;
  settings)
    case "$backend" in
      kde)
        if open_kde_nightcolor_settings; then
          notify-send "Night light" "Opening KDE Night Light settings" 2>/dev/null || true
        else
          notify-send "Night light" "Could not open KDE settings" 2>/dev/null || true
        fi
        ;;
      *)
        pkill -x hyprsunset >/dev/null 2>&1 || true
        if start_nightlight; then
          notify-send "Night light" "Restarted at ${temp}K" 2>/dev/null || true
        else
          notify-send "Night light" "Failed to restart (hyprsunset backend unavailable or unsupported compositor)" 2>/dev/null || true
        fi
        ;;
    esac
    refresh_waybar
    ;;
esac