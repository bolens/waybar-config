#!/usr/bin/env sh
# Shared helpers for compositor-aware clipboard modules.

signal_waybar() {
  pkill -x -RTMIN+9 waybar >/dev/null 2>&1 || true
}

cliphist_available() {
  command -v cliphist >/dev/null 2>&1
}

kde_klipper_available() {
  pgrep -x plasmashell >/dev/null 2>&1 \
    && timeout 1 qdbus6 org.kde.plasmashell /klipper org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1
}

kde_clipboard_history() {
  timeout 2 qdbus6 org.kde.plasmashell /klipper \
    org.kde.klipper.klipper.getClipboardHistoryMenu 2>/dev/null || true
}

kde_clipboard_count() {
  kde_clipboard_history | awk 'NF { count++ } END { print count + 0 }'
}

kde_clipboard_latest() {
  kde_clipboard_history | awk 'NF { print; exit }'
}

kde_open_clipboard() {
  timeout 2 qdbus6 org.kde.plasmashell /klipper \
    org.kde.klipper.klipper.showKlipperPopupMenu >/dev/null 2>&1 || true
}

kde_clear_clipboard() {
  timeout 2 qdbus6 org.kde.plasmashell /klipper \
    org.kde.klipper.klipper.clearClipboardHistory >/dev/null 2>&1 || true
}

kde_edit_clipboard() {
  timeout 2 qdbus6 org.kde.kglobalaccel /component/plasmashell \
    org.kde.kglobalaccel.Component.invokeShortcut \
    "edit_clipboard" >/dev/null 2>&1 || true
}

cliphist_entries() {
  cliphist list 2>/dev/null || true
}

cliphist_count() {
  cliphist_entries | awk 'NF { count++ } END { print count + 0 }'
}

cliphist_latest() {
  cliphist_entries | awk 'NF { print; exit }'
}

cliphist_pick() {
  entries="$(cliphist_entries)"
  [ -n "$entries" ] || return 0

  if command -v rofi >/dev/null 2>&1; then
    selection=$(printf '%s\n' "$entries" \
      | rofi -dmenu -i -p 'Clipboard' \
        -theme-str 'window { width: 780px; } listview { lines: 18; }' 2>/dev/null || true)
  elif command -v wofi >/dev/null 2>&1; then
    selection=$(printf '%s\n' "$entries" | wofi --dmenu -i -p 'Clipboard' 2>/dev/null || true)
  else
    notify-send "Clipboard" "Install rofi or wofi to pick from history" 2>/dev/null || true
    return 1
  fi

  [ -n "$selection" ] || return 0
  printf '%s' "$selection" | cliphist decode | wl-copy
  notify-send "Clipboard" "Copied selection to clipboard" 2>/dev/null || true
}

cliphist_clear() {
  cliphist wipe >/dev/null 2>&1 || true
  notify-send "Clipboard" "Clipboard history cleared" 2>/dev/null || true
}

print_clipboard_status() {
  count="$1"
  latest="$2"
  backend="$3"

  if [ "$count" -eq 0 ] 2>/dev/null; then
    jq -cn \
      --arg backend "$backend" \
      '{text:"", alt:"empty", class:"empty", tooltip:("Clipboard history is empty (" + $backend + ")\n\nLeft: open history · Right: clear · Middle: edit/sync")}'
    return 0
  fi

  tooltip=$(printf 'Clipboard history: %s entries (%s)\nLatest:\n%s\n\nLeft: open history · Right: clear · Middle: edit/sync' \
    "$count" "$backend" "$latest")

  jq -cn \
    --arg text "$count" \
    --arg tooltip "$tooltip" \
    '{text:$text, alt:"normal", class:"normal", tooltip:$tooltip}'
}
