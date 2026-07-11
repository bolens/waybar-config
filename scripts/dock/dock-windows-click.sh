#!/usr/bin/env bash
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

mode="${1:-activate}"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-dock"
state_file="$state_dir/index"
mkdir -p "$state_dir"

signal_dock() {
  "$WAYBAR_SCRIPTS/dock/dock-windows-signal.sh" >/dev/null 2>&1 || true
}

dock_debug() {
  case "${WAYBAR_DEBUG:-}" in
    1 | true | TRUE | yes | YES) ;;
    *) return 0 ;;
  esac
  printf '%s\n' "$*" >>"${XDG_RUNTIME_DIR:-/tmp}/waybar-dock-debug.log"
}

notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send "Dock" "$1" || true
}

trim_title() {
  local s="$1"
  local max="${2:-80}"
  s="${s//$'\n'/ }"
  s="${s//$'\t'/ }"
  s="$(echo "$s" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  if [ "${#s}" -le "$max" ]; then
    printf '%s' "$s"
  else
    printf '%s…' "${s:0:$((max - 1))}"
  fi
}

pick_menu() {
  local theme_dir="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/theme/rofi"
  local rofi_theme="$theme_dir/dock-rofi.rasi"
  if command -v rofi >/dev/null 2>&1; then
    if [ -f "$rofi_theme" ]; then
      rofi -dmenu -i -p "Select window" -theme "$rofi_theme" -me-select-entry '' -me-accept-entry MousePrimary
    else
      rofi -dmenu -i -p "Select window" -me-select-entry '' -me-accept-entry MousePrimary
    fi
  else
    cat
  fi
}

session="unknown"
script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
session="$(detect_compositor)"

if [ "$session" = "hyprland" ] && command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  mapfile -t entries < <(hyprctl clients -j 2>/dev/null | jq -r '.[] | select((.title // "") != "") | "\(.address)|\(.title)"')
  if [ "${#entries[@]}" -eq 0 ]; then
    notify "No open windows"
    exit 0
  fi

  if [ "$mode" = "cycle" ]; then
    idx=0
    if [ -f "$state_file" ]; then
      idx="$(cat "$state_file" 2>/dev/null || echo 0)"
    fi
    idx=$(((idx + 1) % ${#entries[@]}))
    tmp_state="$state_file.tmp.$$"
    printf '%s' "$idx" >"$tmp_state"
    mv -f "$tmp_state" "$state_file"
    addr="${entries[$idx]%%|*}"
    hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1 || true
    signal_dock
    exit 0
  fi

  if [ "$mode" = "close-focused" ]; then
    hyprctl dispatch killactive >/dev/null 2>&1 || true
    signal_dock
    exit 0
  fi

  choices=""
  mapping=""
  for e in "${entries[@]}"; do
    addr="${e%%|*}"
    title="${e#*|}"
    title="$(echo "$title" | sed -E 's/^\[0_\{[^]]+}] ?//')"
    title="$(trim_title "$title" 90)"
    choices+="$title"$'\n'
    mapping+="$title\0$addr\0"
  done

  # If only one window, select it immediately on click
  if [ "${#entries[@]}" -eq 1 ]; then
    addr="${entries[0]%%|*}"
    dock_debug "Only one window, focusing $addr"
    [ -n "$addr" ] && hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1 || true
    signal_dock
    exit 0
  fi

  selected="$(printf '%s' "$choices" | pick_menu || true)"
  [ -n "${selected:-}" ] || exit 0
  # Use null-delimited mapping to find address
  addr=""
  IFS= read -r -d '' -a maparr <<<"$mapping"
  for ((i = 0; i < ${#maparr[@]}; i += 2)); do
    if [ "${maparr[$i]}" = "$selected" ]; then
      addr="${maparr[$((i + 1))]}"
      break
    fi
  done
  dock_debug "Selected window: $addr ($selected)"
  [ -n "$addr" ] && hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1 || true
  signal_dock
  exit 0
fi

if [ "$session" = "kde" ] && command -v qdbus6 >/dev/null 2>&1; then
  raw="$(timeout 2 qdbus6 --literal org.kde.KWin /WindowsRunner org.kde.krunner1.Match windows 2>/dev/null || true)"
  mapfile -t entries < <(printf '%s\n' "$raw" \
    | sed -E 's/\[Argument: \(sssida\{sv\}\) /\n/g' \
    | sed -n -E 's/^"(0_\{[^"]+\})",[[:space:]]*"([^"]+)",[[:space:]]*"[^"]*",[[:space:]]*100,[[:space:]]*1.*/\1|\2/p')

  if [ "${#entries[@]}" -eq 0 ]; then
    notify "No open windows"
    exit 0
  fi

  if [ "$mode" = "cycle" ]; then
    idx=0
    if [ -f "$state_file" ]; then
      idx="$(cat "$state_file" 2>/dev/null || echo 0)"
    fi
    idx=$(((idx + 1) % ${#entries[@]}))
    tmp_state="$state_file.tmp.$$"
    printf '%s' "$idx" >"$tmp_state"
    mv -f "$tmp_state" "$state_file"
    id="${entries[$idx]%%|*}"
    timeout 2 qdbus6 org.kde.KWin /WindowsRunner org.kde.krunner1.Run "$id" "" >/dev/null 2>&1 || true
    signal_dock
    exit 0
  fi

  if [ "$mode" = "close-focused" ]; then
    timeout 2 qdbus6 org.kde.KWin /KWin org.kde.KWin.killWindow >/dev/null 2>&1 || true
    signal_dock
    exit 0
  fi

  choices=""
  mapping=""
  for e in "${entries[@]}"; do
    id="${e%%|*}"
    title="${e#*|}"
    title="$(echo "$title" | sed -E 's/^\[0_\{[^]]+}] ?//')"
    title="$(trim_title "$title" 90)"
    choices+="$title"$'\n'
    mapping+="$title\0$id\0"
  done

  selected="$(printf '%s' "$choices" | pick_menu || true)"
  [ -n "${selected:-}" ] || exit 0
  id=""
  IFS= read -r -d '' -a maparr <<<"$mapping"
  for ((i = 0; i < ${#maparr[@]}; i += 2)); do
    if [ "${maparr[$i]}" = "$selected" ]; then
      id="${maparr[$((i + 1))]}"
      break
    fi
  done
  [ -n "$id" ] && timeout 2 qdbus6 org.kde.KWin /WindowsRunner org.kde.krunner1.Run "$id" "" >/dev/null 2>&1 || true
  signal_dock
  exit 0
fi

notify "Window dock unsupported in this session"
