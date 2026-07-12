#!/usr/bin/env bash
# Refresh workspace strip when Hyprland workspace focus changes.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
# shellcheck source=dock-windows-listener-lock.sh
WAYBAR_LISTENER_LOCK_NAME=hypr-workspaces
. "$script_dir/dock-windows-listener-lock.sh"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

[ "$(detect_compositor)" = "hyprland" ] || exit 0
command -v socat >/dev/null 2>&1 || exit 0

WAYBAR_HOME="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
# Pass signals.* keys (not numbers) so waybar-signal.sh resolves from settings.
SIG_WORKSPACES=workspaces
SIG_KEYBOARD=keyboard_layout
SIG_DOCK_WINDOWS=dock_windows

# Discover Hyprland Instance Signature:
# Hyprland registers active sessions with a unique instance hash.
# We use this signature to locate the correct Unix event socket (.socket2.sock).
signature="${HYPRLAND_INSTANCE_SIGNATURE:-}"
if [ -z "$signature" ] && command -v hyprctl >/dev/null 2>&1; then
  signature="$(hyprctl instances -j 2>/dev/null | jq -r '.[0].instance // empty')"
fi

[ -n "$signature" ] || exit 0
# Prefer XDG runtime socket (Hyprland ≥0.40); fall back to legacy /tmp/hypr.
socket=""
for candidate in \
  "${XDG_RUNTIME_DIR:-}/hypr/${signature}/.socket2.sock" \
  "/tmp/hypr/${signature}/.socket2.sock"; do
  [ -n "$candidate" ] || continue
  if [ -S "$candidate" ]; then
    socket="$candidate"
    break
  fi
done
[ -n "$socket" ] || exit 0

normalize_aw_title() {
  local title="$1"
  title="${title//$'\n'/ }"
  title="${title//$'\t'/ }"
  title="$(printf '%s' "$title" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  title="$(printf '%s' "$title" | sed -E 's/(.*) - Mozilla Firefox/\1/; s/(.*) - Zen Browser/\1/; s/(.*) - Google Chrome/\1/; s/(.*) - Floorp/\1/; s/(.*) - Chromium/\1/; s/(.*) - Brave/\1/; s/(.*) - Vivaldi/\1/')"
  printf '%s' "$title"
}

write_aw_raw() {
  local path="$1"
  local title="$2"
  local tmp="${path}.tmp.$$"
  printf '%s' "$title" >"$tmp"
  mv -f "$tmp" "$path"
}

update_active_window_cache() {
  if ! command -v hyprctl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
  mkdir -p "$cache_dir"

  # Global (focused) window — keeps non-per-output consumers working.
  local title
  title="$(hyprctl activewindow -j 2>/dev/null | jq -r '.title // empty' || true)"
  title="$(normalize_aw_title "$title")"
  write_aw_raw "$cache_dir/active-window-title.raw" "$title"

  # Per-monitor titles for active_window.per_output / empty_desktop_per_output bars.
  local clients_json monitors_json
  clients_json="$(hyprctl clients -j 2>/dev/null || echo '[]')"
  monitors_json="$(hyprctl monitors -j 2>/dev/null || echo '[]')"
  local mon_name mon_id mon_title safe
  while IFS=$'\t' read -r mon_id mon_name; do
    [ -n "$mon_name" ] || continue
    mon_title=$(
      printf '%s' "$clients_json" | jq -r --argjson mid "$mon_id" '
        [.[] | select(.monitor == $mid and ((.mapped // true) == true))]
        | sort_by(.focusHistoryID // 9999)
        | .[0].title // empty
      ' 2>/dev/null || true
    )
    mon_title="$(normalize_aw_title "$mon_title")"
    safe=$(printf '%s' "$mon_name" | sed 's/[^A-Za-z0-9_-]/_/g')
    [ -n "$safe" ] || safe="out_${mon_id}"
    write_aw_raw "$cache_dir/active-window-title-${safe}.raw" "$mon_title"
  done <<EOF
$(printf '%s' "$monitors_json" | jq -r '.[] | "\(.id)\t\(.name)"' 2>/dev/null || true)
EOF
}

# Connect to Hyprland's broadcast event stream using socat:
# Each line emitted by the socket has the format: "eventName>>eventData".
# We read the stream continuously and dispatch real-time signals (SIGRTMIN+N) to Waybar.
# This eliminates module polling lag for workspaces, window titles, keyboard layouts, and docks.
socat -u "UNIX-CONNECT:${socket}" - 2>/dev/null | while IFS= read -r line; do
  event="${line%%>>*}"
  case "$event" in
    workspace | focusedmon | moveworkspace)
      # Invalidate stale cache files
      rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/waybar"/workspaces-*.json 2>/dev/null || true
      "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" "$SIG_WORKSPACES"
      ;;
    activewindow | windowtitle)
      # Title cache is watched by active-window-scroll (zscroll); dock highlight is signal-driven.
      update_active_window_cache
      if [ -x "$WAYBAR_SCRIPTS/dock/dock-windows-signal.sh" ]; then
        "$WAYBAR_SCRIPTS/dock/dock-windows-signal.sh" --force --focus-only
      fi
      ;;
    activelayout)
      "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" "$SIG_KEYBOARD"
      ;;
    openwindow | closewindow | movewindow | changefloatingmode | float)
      update_active_window_cache
      if [ -x "$WAYBAR_SCRIPTS/dock/dock-windows-signal.sh" ]; then
        "$WAYBAR_SCRIPTS/dock/dock-windows-signal.sh"
      else
        "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" "$SIG_DOCK_WINDOWS"
      fi
      ;;
  esac
done
