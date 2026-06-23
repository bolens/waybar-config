#!/usr/bin/env sh
# Standalone runtimes tab script for Waybar custom module
set -eu

script_dir="$(dirname "$0")"
. "$script_dir/side-info-helpers.sh"
. "$script_dir/side-info-cache.sh"
. "$script_dir/side-info-runtimes-summary.sh"

# Output runtimes summary JSON for Waybar
runtimes_summary
