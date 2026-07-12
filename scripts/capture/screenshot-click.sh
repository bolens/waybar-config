#!/usr/bin/env bash
# Screenshot click actions (select / full / window) via capture-lib helpers.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
# shellcheck source=capture-lib.sh
. "$WAYBAR_SCRIPTS/lib/capture-lib.sh"
# shellcheck source=waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

mode="$(normalize_capture_mode "${1:-select}")"
out_name="${2:-${WAYBAR_OUTPUT_NAME:-}}"
if [ -n "$out_name" ]; then
  export WAYBAR_OUTPUT_NAME="$out_name"
fi

capture_per_output=0
_cpo=$(waybar_settings_get '.capture.per_output' 'true')
case "$_cpo" in false | False | FALSE | 0 | no | No | NO | off | Off | OFF) ;; *)
  [ -n "${WAYBAR_OUTPUT_NAME:-}" ] && capture_per_output=1
  ;;
esac

compositor="$(detect_compositor)"
output_tag="$(capture_output_tag "$compositor")"
year="$(date '+%Y')"
save_dir="$(capture_screenshot_base_dir)/$year"

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
        screen)
          # Best-effort: spectacle has no reliable -o output pin; full screen.
          spectacle -b -n -f -o "$outfile"
          ;;
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
        screen)
          if [ "$capture_per_output" -eq 1 ] && [ -n "${WAYBAR_OUTPUT_NAME:-}" ]; then
            # Target the bar's output explicitly (grimblast "output" follows focus).
            grim -o "$WAYBAR_OUTPUT_NAME" "$outfile" && capture_copy_image "$outfile"
          else
            grim "$outfile" && capture_copy_image "$outfile"
          fi
          ;;
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
    if [ "$capture_per_output" -eq 1 ] && [ -n "${WAYBAR_OUTPUT_NAME:-}" ]; then
      grim -o "$WAYBAR_OUTPUT_NAME" "$outfile"
    else
      grim "$outfile"
    fi
    ;;
  *)
    grim "$outfile"
    ;;
esac

capture_copy_image "$outfile"
capture_notify "Screenshot" "Saved: ${outfile##*/}"
