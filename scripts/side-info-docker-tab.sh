#!/usr/bin/env sh
# Standalone docker tab script for Waybar custom module
set -eu

script_dir="$(dirname "$0")"
. "$script_dir/side-info-helpers.sh"
. "$script_dir/side-info-cache.sh"
. "$script_dir/side-info-docker-summary.sh"

# Output docker summary JSON for Waybar
docker_summary
