#!/usr/bin/env bash
# Screenshot module status (static glyph; clicks handled by screenshot-click.sh).
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
# shellcheck source=capture-lib.sh
. "$WAYBAR_SCRIPTS/lib/capture-lib.sh"

compositor="$(detect_compositor)"
backend="$(capture_screenshot_backend "$compositor")"
class="$(capture_screenshot_class "$compositor" "$backend")"
tooltip="$(capture_screenshot_tooltip "$backend")"

jq -cn \
  --arg text "󰹑" \
  --arg class "$class" \
  --arg tooltip "$tooltip" \
  '{text:$text, class:$class, tooltip:$tooltip}'
