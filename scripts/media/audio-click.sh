#!/usr/bin/env bash
# Audio sink volume/mute clicks and scroll (PipeWire/wpctl or pactl).
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

mode="${1:-manage}"

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
if [ -f "$WAYBAR_SCRIPTS/lib/compositor-session.sh" ]; then
  . "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
fi

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

open_sound_settings() {
  compositor=$(detect_compositor)

  case "$compositor" in
    kde)
      for cmd in systemsettings6 systemsettings; do
        if command -v "$cmd" >/dev/null 2>&1; then
          "$cmd" kcm_pulseaudio &
          exit 0
        fi
      done
      ;;
  esac

  # pavucontrol and pwvucontrol work well on both Hyprland and KDE
  for cmd in pavucontrol pwvucontrol; do
    if command -v "$cmd" >/dev/null 2>&1; then
      "$cmd" &
      exit 0
    fi
  done

  # Last resort only on Plasma (already tried above for kde).
  notify-send "Audio" "No sound settings app found" 2>/dev/null || true
}

open_wiremix() {
  if command -v wiremix >/dev/null 2>&1; then
    wiremix &
    exit 0
  fi

  notify-send "Wiremix" "wiremix command not found" 2>/dev/null || true
}

open_sound_selector() {
  if ! command -v rofi >/dev/null 2>&1; then
    notify-send "Audio" "Rofi is not installed" 2>/dev/null || true
    exit 1
  fi

  sinks=$(wpctl status | awk '
    /Sinks:/ {in_sinks=1; next}
    /Sources:/ {in_sinks=0}
    /^[A-Za-z]/ {in_sinks=0}
    in_sinks && /[0-9]+\./ {print}
    /\[Audio\/Sink\]/ {print}
  ')

  list_items=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    is_active=0
    if echo "$line" | grep -Fq "*"; then
      is_active=1
    fi
    clean_line=$(echo "$line" | tr -d '│*' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    id=$(echo "$clean_line" | sed -E 's/^([0-9]+)\..*/\1/')
    name=$(echo "$clean_line" | sed -E 's/^[0-9]+\.\s*(.*)/\1/')
    name=$(echo "$name" | sed -E -e 's/\[vol:[^]]+\]//g' -e 's/\[Audio\/Sink\]//g' -e 's/[[:space:]]+$//')

    if [ "$is_active" -eq 1 ]; then
      list_items="${list_items}* ${name} (ID: ${id})\n"
    else
      list_items="${list_items}  ${name} (ID: ${id})\n"
    fi
  done <<EOF
$sinks
EOF

  audio_theme=$(waybar_settings_get '.rofi.theme' '')
  audio_theme="${audio_theme/\$WAYBAR_HOME/$WAYBAR_HOME}"
  audio_theme="${audio_theme/\$\{WAYBAR_HOME\}/$WAYBAR_HOME}"
  audio_width=$(waybar_settings_get '.rofi.audio.width' '600')

  if [ -n "$audio_theme" ] && [ -f "$audio_theme" ]; then
    choice=$(printf "%b" "$list_items" \
      | rofi -dmenu -i -p "Select Audio Output" -theme "$audio_theme" \
        -theme-str "window {width: ${audio_width}px;}" 2>/dev/null || true)
  else
    choice=$(printf "%b" "$list_items" \
      | rofi -dmenu -i -p "Select Audio Output" \
        -theme-str "window {width: ${audio_width}px;}" 2>/dev/null || true)
  fi

  if [ -n "$choice" ]; then
    new_id=$(printf "%s" "$choice" | sed -E 's/.*\(ID: ([0-9]+)\)/\1/')
    wpctl set-default "$new_id"
    disp_name=$(printf "%s" "$choice" | sed -E -e 's/\s*\(ID: [0-9]+\)//' -e 's/^\*\s*//')
    notify-send "Audio Output" "Switched default sink to $disp_name" 2>/dev/null || true
  fi
}

case "$mode" in
  manage) open_sound_settings ;;
  select) open_sound_selector ;;
  wiremix) open_wiremix ;;
  *) open_sound_settings ;;
esac
