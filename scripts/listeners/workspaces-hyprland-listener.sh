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
settings="$WAYBAR_HOME/data/waybar-settings.json"
sig() {
  local key="$1"
  local fallback="$2"
  if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" --argjson fb "$fallback" '.signals[$k] // $fb' "$settings" 2>/dev/null || printf '%s' "$fallback"
  else
    printf '%s' "$fallback"
  fi
}
SIG_WORKSPACES="$(sig workspaces 16)"
SIG_KEYBOARD="$(sig keyboard_layout 2)"
SIG_DOCK_WINDOWS="$(sig dock_windows 11)"

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

update_active_window_cache() {
  if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    local title
    title="$(hyprctl activewindow -j 2>/dev/null | jq -r '.title // empty' || true)"
    title="${title//$'\n'/ }"
    title="${title//$'\t'/ }"
    title="$(printf '%s' "$title" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
    title="$(printf '%s' "$title" | sed -E 's/(.*) - Mozilla Firefox/\1/; s/(.*) - Zen Browser/\1/; s/(.*) - Google Chrome/\1/; s/(.*) - Floorp/\1/; s/(.*) - Chromium/\1/; s/(.*) - Brave/\1/; s/(.*) - Vivaldi/\1/')"
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
    mkdir -p "$cache_dir"
    echo "$title" >"$cache_dir/active-window-title.raw.tmp"
    mv -f "$cache_dir/active-window-title.raw.tmp" "$cache_dir/active-window-title.raw"
  fi
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
      # Title cache is watched by active-window-scroll (zscroll); no Waybar signal.
      update_active_window_cache
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
