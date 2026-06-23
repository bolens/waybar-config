#!/usr/bin/env sh
set -eu

script_dir="${0%/*}"
# shellcheck source=compositor-session.sh
. "$script_dir/compositor-session.sh"
# shellcheck source=capture-lib.sh
. "$script_dir/capture-lib.sh"

compositor="$(detect_compositor)"
backend="$(capture_screenshot_backend "$compositor")"
class="$(capture_screenshot_class "$compositor" "$backend")"
tooltip="$(capture_screenshot_tooltip "$backend")"

jq -cn \
  --arg text "󰹑" \
  --arg class "$class" \
  --arg tooltip "$tooltip" \
  '{text:$text, class:$class, tooltip:$tooltip}'
