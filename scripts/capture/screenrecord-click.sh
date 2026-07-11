#!/usr/bin/env bash
# shellcheck disable=SC2154 # cache_dir / screenrecord_* assigned in capture-lib.sh (ShellCheck misses top-level assigns there)
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
# shellcheck source=../lib/compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
# shellcheck source=../lib/capture-lib.sh
. "$WAYBAR_SCRIPTS/lib/capture-lib.sh"

mode="$(normalize_capture_mode "${1:-select}")"

mkdir -p "$cache_dir"

# stop_recording:
# Gracefully stops screen recording.
# To prevent corruption of the MP4 video container, we send SIGINT (Interrupt) instead of SIGKILL.
# This allows wf-recorder/spectacle to write the file index and close the stream properly.
stop_recording() {
  if pid="$(capture_wf_running_pid)"; then
    kill -INT "$pid" 2>/dev/null || true
    rm -f "$screenrecord_pid_file"
    out=""
    if [ -f "$screenrecord_meta_file" ]; then
      out="$(cat "$screenrecord_meta_file" 2>/dev/null || true)"
    fi
    if [ -n "$out" ]; then
      capture_notify "Recording" "Saved: ${out##*/}"
    else
      capture_notify "Recording" "Stopped"
    fi
    capture_signal_screenrecord
    exit 0
  fi

  if capture_spectacle_recording; then
    pkill -INT -f 'spectacle.*--record' >/dev/null 2>&1 || true
    capture_notify "Recording" "Stopped Spectacle recording"
    capture_signal_screenrecord
    exit 0
  fi
}

start_spectacle_recording() {
  case "$mode" in
    selection) spectacle --record r >/dev/null 2>&1 & ;;
    window) spectacle --record w >/dev/null 2>&1 & ;;
    screen) spectacle --record s >/dev/null 2>&1 & ;;
    *) spectacle --record s >/dev/null 2>&1 & ;;
  esac
  pid="$!"
  capture_notify "Recording" "Started (Spectacle backend)"
  capture_signal_screenrecord
  (
    while kill -0 "$pid" 2>/dev/null; do
      sleep 2
    done
    capture_signal_screenrecord
  ) &
}

# start_wf_recording:
# Starts a new recording using wf-recorder. Supports selecting a region (slurp),
# active window coordinates, or the entire screen.
start_wf_recording() {
  compositor="$(detect_compositor)"
  output_tag="$(capture_output_tag "$compositor")"
  record_fps="$(capture_screenrecord_fps)"
  year="$(date '+%Y')"
  save_dir="$(capture_screenrecord_base_dir)/$year"

  if ! mkdir -p "$save_dir" 2>/dev/null; then
    capture_notify "Recording" "Cannot create $save_dir"
    exit 1
  fi

  outfile="$(capture_build_screenrecord_path "$mode" "$output_tag" "wfrec" "mp4" "$record_fps")"

  case "$mode" in
    selection)
      if ! command -v slurp >/dev/null 2>&1; then
        capture_notify "Recording" "slurp not found for selection mode"
        exit 1
      fi
      geom="$(slurp)"
      [ -n "$geom" ] || exit 0
      wf-recorder -r "$record_fps" -g "$geom" -f "$outfile" >/dev/null 2>&1 &
      ;;
    window)
      geom=""
      # Query the active window coordinates from Hyprland and format into standard "X,Y WxH" geometry
      if [ "$compositor" = "hyprland" ] && command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        geom="$(hyprctl activewindow -j 2>/dev/null | jq -r 'if (.at and .size) then (.at[0]|tostring)+","+(.at[1]|tostring)+" "+(.size[0]|tostring)+"x"+(.size[1]|tostring) else "" end')"
      fi

      if [ -n "$geom" ]; then
        wf-recorder -r "$record_fps" -g "$geom" -f "$outfile" >/dev/null 2>&1 &
      elif [ "$compositor" = "kde" ] && command -v spectacle >/dev/null 2>&1; then
        spectacle --record w >/dev/null 2>&1 &
        pid="$!"
        capture_notify "Recording" "Started active-window recording (Spectacle)"
        capture_signal_screenrecord
        (
          while kill -0 "$pid" 2>/dev/null; do
            sleep 2
          done
          capture_signal_screenrecord
        ) &
        exit 0
      else
        if ! command -v slurp >/dev/null 2>&1; then
          capture_notify "Recording" "No window geometry backend found"
          exit 1
        fi
        geom="$(slurp)"
        [ -n "$geom" ] || exit 0
        wf-recorder -r "$record_fps" -g "$geom" -f "$outfile" >/dev/null 2>&1 &
      fi
      ;;
    screen)
      wf-recorder -r "$record_fps" -f "$outfile" >/dev/null 2>&1 &
      ;;
    *)
      wf-recorder -r "$record_fps" -f "$outfile" >/dev/null 2>&1 &
      ;;
  esac

  pid="$!"

  # Write PID and metadata files atomically to avoid read races with screenrecord-status
  tmp_pid="$screenrecord_pid_file.tmp.$$"
  printf '%s' "$pid" >"$tmp_pid"
  mv -f "$tmp_pid" "$screenrecord_pid_file"

  tmp_meta="$screenrecord_meta_file.tmp.$$"
  printf '%s' "$outfile" >"$tmp_meta"
  mv -f "$tmp_meta" "$screenrecord_meta_file"

  capture_notify "Recording" "Started: ${outfile##*/}"
  capture_signal_screenrecord
  (
    while kill -0 "$pid" 2>/dev/null; do
      sleep 2
    done
    rm -f "$screenrecord_pid_file"
    capture_signal_screenrecord
  ) &
}

stop_recording

compositor="$(detect_compositor)"

if ! command -v wf-recorder >/dev/null 2>&1; then
  if [ "$compositor" = "kde" ] && command -v spectacle >/dev/null 2>&1; then
    start_spectacle_recording
    exit 0
  fi
  capture_notify "Recording" "wf-recorder not found"
  exit 1
fi

start_wf_recording
