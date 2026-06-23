#!/usr/bin/env bash
set -eu

script_dir="${0%/*}"
# shellcheck source=waybar-settings.sh
. "$script_dir/waybar-settings.sh"

WAYBAR_HOME="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
exec env NUT_TARGET="$(waybar_services_nut_target)" "$WAYBAR_HOME/scripts/ups-status.sh" "$@"
