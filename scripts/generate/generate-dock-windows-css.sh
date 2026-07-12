#!/usr/bin/env bash
# Generate dock window slot layout from dock_windows.slot_count.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/css-selectors-lib.sh"

settings="${WAYBAR_HOME}/data/waybar-settings.json"
out="$WAYBAR_HOME/theme/dock-windows.generated.css"
mkdir -p "$WAYBAR_HOME/theme"

# Match generate-dock-windows-modules.sh: clamp 1–16, default 12.
slot_count="$(waybar_css_slot_count "$settings" dock_windows 12 1 16)"

hit="$(waybar_css_id_range '#custom-dock-win-' "$slot_count" '.dock-win-hit')"
inactive="$(waybar_css_id_range '#custom-dock-win-' "$slot_count" '.dock-win-inactive')"
active="$(waybar_css_id_range '#custom-dock-win-' "$slot_count" '.dock-win-active')"
hit_hover="$(waybar_css_id_range '#custom-dock-win-' "$slot_count" '.dock-win-hit:hover')"
hidden="$(waybar_css_id_range '#custom-dock-win-' "$slot_count" '.hidden')"

cat >"$out" <<EOF
/* Generated from dock_windows.slot_count — do not edit by hand */

${hit} {
    background: transparent;
    background-image: none;
    border: none;
    box-shadow: none;
    padding: 0 12px;
    margin: 0;
    min-width: 24px;
    border-radius: 8px;
    transition:
        color 280ms cubic-bezier(0.4, 0, 0.2, 1),
        opacity 280ms cubic-bezier(0.4, 0, 0.2, 1),
        background-color 300ms cubic-bezier(0.4, 0, 0.2, 1);
}

${inactive} {
    opacity: 0.7;
}

${active} {
    opacity: 1;
}

${hit_hover} {
    opacity: 1;
}

${hidden} {
    background: transparent;
    margin: 0;
    padding: 0;
    min-width: 0;
}
EOF
