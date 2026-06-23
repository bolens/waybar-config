#!/usr/bin/env sh
# Compositor-aware clipboard manager actions for Waybar.
set -eu

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
. "$script_dir/compositor-session.sh"
# shellcheck source=clipboard-lib.sh
. "$script_dir/clipboard-lib.sh"

action="${1:-pick}"
compositor="$(detect_compositor)"

signal_refresh() {
  signal_waybar
}

hyprland_sync_primary() {
  if command -v wl-copy >/dev/null 2>&1 && command -v wl-paste >/dev/null 2>&1; then
    wl-paste -p 2>/dev/null | wl-copy 2>/dev/null || true
    notify-send "Clipboard" "Primary selection copied to clipboard" 2>/dev/null || true
    signal_refresh
  fi
}

case "$compositor" in
  kde)
    case "$action" in
      pick|open)
        kde_open_clipboard
        ;;
      clear)
        kde_clear_clipboard
        notify-send "Clipboard" "Clipboard history cleared" 2>/dev/null || true
        signal_refresh
        ;;
      edit|sync)
        kde_edit_clipboard
        ;;
      *)
        kde_open_clipboard
        ;;
    esac
    ;;
  hyprland)
    case "$action" in
      pick|open)
        if ! cliphist_available; then
          notify-send "Clipboard" "cliphist is not installed" 2>/dev/null || true
          exit 0
        fi
        if [ "${WAYBAR_CLIPBOARD_CLICK_NO_UI:-0}" = "1" ]; then
          cliphist_entries
          exit 0
        fi
        cliphist_pick
        signal_refresh
        ;;
      clear)
        if cliphist_available; then
          cliphist_clear
          signal_refresh
        fi
        ;;
      edit|sync)
        hyprland_sync_primary
        ;;
      *)
        cliphist_pick
        signal_refresh
        ;;
    esac
    ;;
  *)
    case "$action" in
      clear)
        if cliphist_available; then
          cliphist_clear
        elif kde_klipper_available; then
          kde_clear_clipboard
          notify-send "Clipboard" "Clipboard history cleared" 2>/dev/null || true
        fi
        signal_refresh
        ;;
      edit|sync)
        if kde_klipper_available; then
          kde_edit_clipboard
        else
          hyprland_sync_primary
        fi
        ;;
      *)
        if kde_klipper_available; then
          kde_open_clipboard
        elif cliphist_available; then
          cliphist_pick
          signal_refresh
        else
          notify-send "Clipboard" "No clipboard manager found" 2>/dev/null || true
        fi
        ;;
    esac
    ;;
esac
