#!/usr/bin/env sh
# Query all virtual desktops status for Waybar custom/workspaces.
set -eu
script_dir="${0%/*}"
output="${1:-}"
if [ -n "$output" ]; then
  export WAYBAR_OUTPUT_NAME="$output"
fi
"$script_dir/workspaces-query.py" 2>/dev/null || printf '{"compositor":"unknown","current":"","desktops":[]}\n'
