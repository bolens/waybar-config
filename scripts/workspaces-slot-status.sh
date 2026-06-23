#!/usr/bin/env sh
# Workspace slot glyph + click target (pill renders on custom/workspaces behind this).
set -eu

script_dir="${0%/*}"
position="${1:-}"
output="${2:-}"

if [ -z "$position" ]; then
  printf '{"text":"","tooltip":"","class":["hidden"]}\n'
  exit 0
fi

if [ -n "$output" ]; then
  export WAYBAR_OUTPUT_NAME="$output"
fi

desktop="$("$script_dir/workspaces-query.py" "$position" 2>/dev/null || true)"

if [ -z "$desktop" ] || [ "$desktop" = "null" ]; then
  printf '{"text":"","tooltip":"","class":["hidden"]}\n'
  exit 0
fi

printf '%s\n' "$desktop"
