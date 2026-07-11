#!/usr/bin/env sh
# Standalone docker tab script for Waybar custom module
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="$(dirname "$0")"
. "$WAYBAR_SCRIPTS/lib/side-info-helpers.sh"
. "$script_dir/side-info-cache.sh"
. "$script_dir/side-info-docker-summary.sh"

# Output docker summary JSON for Waybar
docker_summary
