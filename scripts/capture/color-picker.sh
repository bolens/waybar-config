#!/usr/bin/env sh
# Color picker — hyprpicker on Hyprland, kcolorchooser on Plasma.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

copy_color() {
  color="$1"
  [ -n "$color" ] || return 1
  if command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$color" | wl-copy
  elif command -v xclip >/dev/null 2>&1; then
    printf '%s' "$color" | xclip -selection clipboard
  fi
  notify-send -t 4000 "Color Picker" "Copied color: $color" \
    -h string:x-canonical-private-synchronous:color-picker 2>/dev/null || true
}

comp="$(detect_compositor)"
case "$comp" in
  hyprland)
    if ! command -v hyprpicker >/dev/null 2>&1; then
      notify-send "Color Picker" "hyprpicker not installed" 2>/dev/null || true
      exit 1
    fi
    color="$(hyprpicker -a 2>/dev/null || true)"
    copy_color "$color" || true
    ;;
  kde)
    if command -v kcolorchooser >/dev/null 2>&1; then
      color="$(kcolorchooser --print 2>/dev/null || true)"
      copy_color "$color" || true
      exit 0
    fi
    if command -v spectacle >/dev/null 2>&1; then
      # Region grab as a last resort (not a true picker).
      spectacle -b -n -r >/dev/null 2>&1 &
      exit 0
    fi
    notify-send "Color Picker" "Install kcolorchooser (or spectacle)" 2>/dev/null || true
    exit 1
    ;;
  *)
    if command -v hyprpicker >/dev/null 2>&1; then
      color="$(hyprpicker -a 2>/dev/null || true)"
      copy_color "$color" || true
    elif command -v kcolorchooser >/dev/null 2>&1; then
      color="$(kcolorchooser --print 2>/dev/null || true)"
      copy_color "$color" || true
    else
      notify-send "Color Picker" "No color picker available" 2>/dev/null || true
      exit 1
    fi
    ;;
esac
