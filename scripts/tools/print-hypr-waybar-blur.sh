#!/usr/bin/env bash
# Echo a suggested Hyprland layerrule snippet for Waybar blur.
# Does not write or modify any config files.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cat <<'EOF'
# Suggested Hyprland rules for Waybar blur (paste into hyprland.conf / a sourced drop-in).
# Requires decoration:blur enabled. Adjust ignore_alpha if the bar looks too washed out.

layerrule = blur, waybar
layerrule = ignorezero, waybar
# Optional: ignore near-transparent pixels so only solid module chrome blurs
# layerrule = ignorealpha 0.2, waybar

# If you use floating / multi-bar setups, also try:
# layerrule = blur, ^(waybar)$
EOF
