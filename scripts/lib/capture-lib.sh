#!/usr/bin/env bash
# Shared helpers for screenshot and screen recording modules.

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
screenrecord_pid_file="$cache_dir/screenrecord.pid"
screenrecord_meta_file="$cache_dir/screenrecord.meta"

_capture_scripts_dir="${WAYBAR_SCRIPTS:-${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts}/lib"
if ! type waybar_settings_get >/dev/null 2>&1; then
  if [ -f "$_capture_scripts_dir/waybar-settings.sh" ]; then
    # shellcheck source=waybar-settings.sh
    . "$_capture_scripts_dir/waybar-settings.sh"
  fi
fi

capture_screenshot_base_dir() {
  if type waybar_settings_get >/dev/null 2>&1; then
    waybar_settings_get '.capture.screenshot_dir' '/mnt/media/screenshots'
  else
    printf '%s' '/mnt/media/screenshots'
  fi
}

capture_screenrecord_base_dir() {
  if type waybar_settings_get >/dev/null 2>&1; then
    waybar_settings_get '.capture.screenrecord_dir' '/mnt/media/screenrecordings'
  else
    printf '%s' '/mnt/media/screenrecordings'
  fi
}

capture_screenrecord_fps() {
  if [ -n "${WAYBAR_SCREENREC_FPS:-}" ]; then
    printf '%s' "$WAYBAR_SCREENREC_FPS"
    return
  fi
  if type waybar_settings_get >/dev/null 2>&1; then
    waybar_settings_get '.capture.screenrecord_fps' '60'
  else
    printf '%s' '60'
  fi
}

capture_notify() {
  notify-send "$1" "$2" 2>/dev/null || true
}

capture_signal_screenrecord() {
  pkill -x -RTMIN+6 waybar >/dev/null 2>&1 || true
}

normalize_capture_mode() {
  case "${1:-select}" in
    select) printf 'selection' ;;
    full) printf 'screen' ;;
    selection|screen|window) printf '%s' "$1" ;;
    *) printf 'selection' ;;
  esac
}

capture_sanitize_tag() {
  raw="$1"
  cleaned=$(printf '%s' "$raw" | sed 's/[^A-Za-z0-9._-]/_/g')
  if [ -n "$cleaned" ]; then
    printf '%s' "$cleaned"
  else
    printf 'unknown'
  fi
}

capture_output_tag() {
  compositor="$1"
  if [ -n "${WAYBAR_OUTPUT_NAME:-}" ]; then
    capture_sanitize_tag "$WAYBAR_OUTPUT_NAME"
    return 0
  fi
  case "$compositor" in
    hyprland)
      if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        out=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused==true) | .name' | head -n1 || true)
        if [ -n "$out" ]; then
          capture_sanitize_tag "$out"
          return 0
        fi
      fi
      ;;
    kde)
      # Best-effort: first connected output from kscreen-doctor.
      if command -v kscreen-doctor >/dev/null 2>&1; then
        out=$(kscreen-doctor -o 2>/dev/null | awk '/Output:/ {print $2; exit}' || true)
        if [ -n "$out" ]; then
          capture_sanitize_tag "$out"
          return 0
        fi
      fi
      ;;
  esac
  printf 'unknown'
}

capture_screenshot_backend() {
  compositor="$1"
  case "$compositor" in
    kde)
      if command -v spectacle >/dev/null 2>&1; then
        printf 'spectacle'
        return 0
      fi
      ;;
    hyprland)
      if command -v grimblast >/dev/null 2>&1; then
        printf 'grimblast'
        return 0
      fi
      if command -v grim >/dev/null 2>&1; then
        printf 'grim'
        return 0
      fi
      ;;
    *)
      if command -v grim >/dev/null 2>&1; then
        printf 'grim'
        return 0
      fi
      ;;
  esac
  printf 'unknown'
}

capture_screenrecord_backend() {
  compositor="$1"
  case "$compositor" in
    kde)
      if command -v spectacle >/dev/null 2>&1; then
        printf 'spectacle'
        return 0
      fi
      if command -v wf-recorder >/dev/null 2>&1; then
        printf 'wf-recorder'
        return 0
      fi
      ;;
    hyprland)
      if command -v wf-recorder >/dev/null 2>&1; then
        printf 'wf-recorder'
        return 0
      fi
      ;;
    *)
      if command -v wf-recorder >/dev/null 2>&1; then
        printf 'wf-recorder'
        return 0
      fi
      if command -v spectacle >/dev/null 2>&1; then
        printf 'spectacle'
        return 0
      fi
      ;;
  esac
  printf 'unknown'
}

capture_screenshot_class() {
  compositor="$1"
  backend="$2"
  case "$compositor" in
    kde) printf 'kde' ;;
    hyprland) printf 'hyprland' ;;
    *)
      if [ "$backend" = "unknown" ]; then
        printf 'unknown'
      else
        printf 'ready'
      fi
      ;;
  esac
}

capture_build_screenshot_path() {
  mode_name="$1"
  output_name="$2"
  backend_name="$3"
  ext="$4"
  year="$(date '+%Y')"
  save_dir="$(capture_screenshot_base_dir)/$year"
  stamp_name="$(date '+%Y-%d-%m_%H%M%S')"
  printf '%s/%s-%s-%s-%s.%s' "$save_dir" "$stamp_name" "$mode_name" "$output_name" "$backend_name" "$ext"
}

capture_build_screenrecord_path() {
  mode_name="$1"
  output_name="$2"
  backend_name="$3"
  ext="$4"
  fps_name="$5"
  year="$(date '+%Y')"
  save_dir="$(capture_screenrecord_base_dir)/$year"
  stamp_name="$(date '+%Y-%d-%m_%H%M%S')"
  printf '%s/%s-%s-%s-%s-%sfps.%s' "$save_dir" "$stamp_name" "$mode_name" "$output_name" "$backend_name" "$fps_name" "$ext"
}

capture_copy_image() {
  file="$1"
  if command -v wl-copy >/dev/null 2>&1; then
    wl-copy < "$file" 2>/dev/null || true
  fi
}

capture_wf_running_pid() {
  if [ -f "$screenrecord_pid_file" ]; then
    pid="$(cat "$screenrecord_pid_file" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      printf '%s' "$pid"
      return 0
    fi
  fi
  return 1
}

capture_spectacle_recording() {
  pgrep -af 'spectacle.*--record' >/dev/null 2>&1
}

capture_recording_active() {
  capture_wf_running_pid >/dev/null 2>&1 || capture_spectacle_recording
}

capture_screenshot_tooltip() {
  backend="$1"
  printf 'Screenshot\nLeft: Select area\nMiddle: Active window\nRight: Full screen\nBackend: %s' "$backend"
}

capture_screenrecord_idle_tooltip() {
  backend="$1"
  printf 'Screen recorder\nLeft: Select area\nMiddle: Active window\nRight: Full screen\nBackend: %s' "$backend"
}

capture_screenrecord_active_tooltip() {
  backend="$1"
  outfile=""
  if [ -f "$screenrecord_meta_file" ]; then
    outfile="$(cat "$screenrecord_meta_file" 2>/dev/null || true)"
  fi
  if [ -n "$outfile" ]; then
    printf 'Screen recording active\nFile: %s\nClick any button to stop\nBackend: %s' "${outfile##*/}" "$backend"
  else
    printf 'Screen recording active\nClick any button to stop\nBackend: %s' "$backend"
  fi
}

capture_emit_screenrecord_status() {
  compositor="$1"
  backend="$(capture_screenrecord_backend "$compositor")"

  if capture_recording_active; then
    tooltip="$(capture_screenrecord_active_tooltip "$backend")"
    jq -cn \
      --arg text "󰑋" \
      --arg class "recording" \
      --arg tooltip "$tooltip" \
      '{text:$text, class:$class, tooltip:$tooltip}'
    return 0
  fi

  tooltip="$(capture_screenrecord_idle_tooltip "$backend")"
  class="idle"
  if [ "$backend" = "unknown" ]; then
    class="unknown"
  elif [ "$compositor" = "kde" ]; then
    class="kde"
  elif [ "$compositor" = "hyprland" ]; then
    class="hyprland"
  fi

  jq -cn \
    --arg text "󰻃" \
    --arg class "$class" \
    --arg tooltip "$tooltip" \
    '{text:$text, class:$class, tooltip:$tooltip}'
}

capture_screenrecord_state_key() {
  compositor="$1"
  if capture_recording_active; then
    printf 'recording:%s' "$(capture_screenrecord_backend "$compositor")"
    return 0
  fi
  printf 'idle:%s' "$(capture_screenrecord_backend "$compositor")"
}
