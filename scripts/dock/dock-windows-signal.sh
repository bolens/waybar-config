#!/usr/bin/env sh
# Debounced Waybar refresh for the dock-windows module.
# Usage: dock-windows-signal.sh [--force] [--focus-only]
#
# --focus-only: keep the window list cache; slots recompute active from
#   active-window-title*.raw (instant highlight without qdbus Match).
# Full refresh (default): drop list caches so open/close/reorder is picked up.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

force=0
focus_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force | -f) force=1 ;;
    --focus-only) focus_only=1 ;;
    *) break ;;
  esac
  shift
done

# shellcheck source=waybar-cache-helpers.sh
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
debounce_stamp="${XDG_RUNTIME_DIR:-/tmp}/waybar-dock-signal.stamp"
# Default 80ms — old 1s default made the active highlight feel lagged.
debounce_ms="${WAYBAR_DOCK_SIGNAL_DEBOUNCE_MS:-80}"
settings="$WAYBAR_HOME/data/waybar-settings.json"
dock_sig=11
if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
  dock_sig="$(jq -r '.signals.dock_windows // 11' "$settings")"
fi

now_ms() {
  if command -v date >/dev/null 2>&1; then
    ms=$(date +%s%3N 2>/dev/null || true)
    case "$ms" in
      '' | *[!0-9]*) ;;
      *)
        case "$ms" in
          *%*) ;;
          *)
            printf '%s' "$ms"
            return 0
            ;;
        esac
        ;;
    esac
  fi
  printf '%s' "$(($(date +%s) * 1000))"
}

if [ "$force" != 1 ]; then
  now=$(now_ms)
  last=0
  if [ -f "$debounce_stamp" ]; then
    last=$(cat "$debounce_stamp" 2>/dev/null || printf '0')
    case "$last" in
      '' | *[!0-9]*) last=0 ;;
    esac
  fi
  if [ "$((now - last))" -lt "$debounce_ms" ] 2>/dev/null; then
    exit 0
  fi
  mkdir -p "$(dirname "$debounce_stamp")"
  printf '%s' "$now" >"$debounce_stamp" 2>/dev/null || true
else
  mkdir -p "$(dirname "$debounce_stamp")"
  now_ms >"$debounce_stamp" 2>/dev/null || true
fi

set --
[ -f "$cache_dir/dock-windows-status.json" ] && set -- "$@" "$cache_dir/dock-windows-status.json"
if [ "$focus_only" != 1 ]; then
  [ -f "$cache_dir/dock-windows-list.json" ] && set -- "$@" "$cache_dir/dock-windows-list.json"
  if [ -d "$cache_dir" ]; then
    for f in "$cache_dir"/dock-windows-status.*.json "$cache_dir"/dock-windows-list.*.json; do
      [ -f "$f" ] || continue
      set -- "$@" "$f"
    done
  fi
  rm -f "$cache_dir"/dock-windows-list.json "$cache_dir"/dock-windows-list.*.json 2>/dev/null || true
else
  if [ -d "$cache_dir" ]; then
    for f in "$cache_dir"/dock-windows-status.*.json; do
      [ -f "$f" ] || continue
      set -- "$@" "$f"
    done
  fi
fi
"$WAYBAR_SCRIPTS/lib/waybar-signal.sh" "$dock_sig" "$@"
