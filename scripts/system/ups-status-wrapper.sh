#!/usr/bin/env bash
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
# shellcheck source=waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

WAYBAR_HOME="${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
exec env NUT_TARGET="$(waybar_services_nut_target)" "$WAYBAR_SCRIPTS/system/ups-status.sh" "$@"
