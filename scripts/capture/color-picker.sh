#!/usr/bin/env sh
# Premium color picker utility tray command using hyprpicker and notify-send.
set -eu

color=$(hyprpicker -a)
if [ -n "$color" ]; then
  notify-send -t 4000 "Color Picker" "Copied color: $color" -h string:x-canonical-private-synchronous:color-picker
fi
