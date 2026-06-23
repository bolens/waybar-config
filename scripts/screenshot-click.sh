#!/usr/bin/env sh
set -eu

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
. "$script_dir/compositor-session.sh"
# shellcheck source=capture-lib.sh
. "$script_dir/capture-lib.sh"

mode="$(normalize_capture_mode "${1:-select}")"

compositor="$(detect_compositor)"
output_tag="$(capture_output_tag "$compositor")"
year="$(date '+%Y')"
save_dir="/mnt/media/screenshots/$year"

if ! mkdir -p "$save_dir" 2>/dev/null; then
  capture_notify "Screenshot" "Cannot create $save_dir"
  exit 1
fi

case "$compositor" in
  kde)
    if command -v spectacle >/dev/null 2>&1; then
      outfile="$(capture_build_screenshot_path "$mode" "$output_tag" "spectacle" "png")"
      case "$mode" in
        selection) spectacle -b -n -r -o "$outfile" ;;
        screen) spectacle -b -n -f -o "$outfile" ;;
        window) spectacle -b -n -a -o "$outfile" ;;
        *) spectacle -b -n -r -o "$outfile" ;;
      esac
      capture_copy_image "$outfile"
      capture_notify "Screenshot" "Saved: ${outfile##*/}"
      exit 0
    fi
    capture_notify "Screenshot" "spectacle not found"
    exit 1
    ;;
  hyprland)
    if command -v grimblast >/dev/null 2>&1; then
      outfile="$(capture_build_screenshot_path "$mode" "$output_tag" "grimblast" "png")"
      case "$mode" in
        selection) grimblast --freeze copysave area "$outfile" ;;
        screen) grim "$outfile" && capture_copy_image "$outfile" ;;
        window) grimblast copysave active "$outfile" ;;
        *) grimblast --freeze copysave area "$outfile" ;;
      esac
      capture_notify "Screenshot" "Saved: ${outfile##*/}"
      exit 0
    fi
    ;;
esac

if ! command -v grim >/dev/null 2>&1; then
  capture_notify "Screenshot" "grim not found"
  exit 1
fi

outfile="$(capture_build_screenshot_path "$mode" "$output_tag" "grim" "png")"

case "$mode" in
  selection)
    if ! command -v slurp >/dev/null 2>&1; then
      capture_notify "Screenshot" "slurp not found for selection mode"
      exit 1
    fi
    geom="$(slurp)"
    [ -n "$geom" ] || exit 0
    grim -g "$geom" "$outfile"
    ;;
  window)
    geom=""
    if [ "$compositor" = "hyprland" ] && command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
      geom="$(hyprctl activewindow -j 2>/dev/null | jq -r 'if (.at and .size) then (.at[0]|tostring)+","+(.at[1]|tostring)+" "+(.size[0]|tostring)+"x"+(.size[1]|tostring) else "" end')"
    fi
    if [ -n "$geom" ]; then
      grim -g "$geom" "$outfile"
    elif command -v slurp >/dev/null 2>&1; then
      geom="$(slurp)"
      [ -n "$geom" ] || exit 0
      grim -g "$geom" "$outfile"
    else
      grim "$outfile"
    fi
    ;;
  screen)
    grim "$outfile"
    ;;
  *)
    grim "$outfile"
    ;;
esac

capture_copy_image "$outfile"
capture_notify "Screenshot" "Saved: ${outfile##*/}"
