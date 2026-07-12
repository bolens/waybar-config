#!/usr/bin/env bash
# Per-slot dock-windows actions (no rofi — active-window module owns the picker).
# Usage: dock-windows-click.sh <focus|close|cycle|close-focused> [slot] [OUTPUT]
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

mode="${1:-focus}"
slot_or_out="${2:-}"
maybe_out="${3:-}"

slot=""
output_arg=""
case "$mode" in
  focus | close)
    slot="$slot_or_out"
    output_arg="$maybe_out"
    ;;
  cycle | close-focused | activate)
    # activate kept as alias of cycle for old bindings
    output_arg="$slot_or_out"
    ;;
  *)
    output_arg="$slot_or_out"
    ;;
esac

if [ -n "$output_arg" ]; then
  export WAYBAR_OUTPUT_NAME="$output_arg"
fi
: "${WAYBAR_OUTPUT_NAME:=}"

# shellcheck source=waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck source=dock-windows-kde-lib.sh
. "$WAYBAR_SCRIPTS/lib/dock-windows-kde-lib.sh"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

state_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-dock"
state_file="$state_dir/index"
mkdir -p "$state_dir"

signal_dock() {
  # Drop list caches so slots re-query immediately.
  cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
  rm -f "$cache_dir"/dock-windows-list.json "$cache_dir"/dock-windows-list.*.json 2>/dev/null || true
  "$WAYBAR_SCRIPTS/dock/dock-windows-signal.sh" >/dev/null 2>&1 || true
}

notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send "Dock" "$1" || true
}

list_json() {
  "$WAYBAR_SCRIPTS/dock/dock-windows-query.sh" "${WAYBAR_OUTPUT_NAME:-}" 2>/dev/null || echo '[]'
}

focus_id() {
  local id="$1"
  local session
  session="$(detect_compositor)"
  [ -n "$id" ] || return 0
  if [ "$session" = "hyprland" ]; then
    hyprctl dispatch focuswindow "address:$id" >/dev/null 2>&1 || true
  elif [ "$session" = "kde" ]; then
    timeout 2 qdbus6 org.kde.KWin /WindowsRunner org.kde.krunner1.Run "$id" "" >/dev/null 2>&1 || true
  fi
}

close_id() {
  local id="$1"
  local session
  session="$(detect_compositor)"
  if [ "$session" = "hyprland" ]; then
    if [ -n "$id" ]; then
      hyprctl dispatch closewindow "address:$id" >/dev/null 2>&1 || true
    else
      hyprctl dispatch killactive >/dev/null 2>&1 || true
    fi
  elif [ "$session" = "kde" ]; then
    # Focus then kill (WindowsRunner has no direct close-by-id).
    [ -n "$id" ] && focus_id "$id"
    timeout 2 qdbus6 org.kde.KWin /KWin org.kde.KWin.killWindow >/dev/null 2>&1 || true
  fi
}

session="$(detect_compositor)"
case "$session" in
  hyprland | kde) ;;
  *)
    notify "Window dock unsupported in this session"
    exit 0
    ;;
esac

if [ "$session" = "kde" ] && ! dock_windows_kde_has_qdbus; then
  notify "Install qt6-tools (qdbus6)"
  exit 0
fi

case "$mode" in
  focus)
    if [ -z "$slot" ] || ! [[ "$slot" =~ ^[0-9]+$ ]]; then
      exit 0
    fi
    id=$(list_json | jq -r --argjson i "$slot" '.[$i].id // empty')
    focus_id "$id"
    signal_dock
    ;;
  close)
    if [ -z "$slot" ] || ! [[ "$slot" =~ ^[0-9]+$ ]]; then
      exit 0
    fi
    id=$(list_json | jq -r --argjson i "$slot" '.[$i].id // empty')
    close_id "$id"
    signal_dock
    ;;
  close-focused)
    close_id ""
    signal_dock
    ;;
  cycle | activate)
    mapfile -t ids < <(list_json | jq -r '.[].id // empty')
    if [ "${#ids[@]}" -eq 0 ]; then
      notify "No open windows"
      exit 0
    fi
    idx=0
    if [ -f "$state_file" ]; then
      idx="$(cat "$state_file" 2>/dev/null || echo 0)"
    fi
    idx=$(((idx + 1) % ${#ids[@]}))
    printf '%s' "$idx" >"$state_file.tmp.$$"
    mv -f "$state_file.tmp.$$" "$state_file"
    focus_id "${ids[$idx]}"
    signal_dock
    ;;
  *)
    exit 1
    ;;
esac
