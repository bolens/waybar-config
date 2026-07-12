#!/usr/bin/env bash
# Generate drawer shell / handle layout from css-selectors-lib.sh SoT.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/css-selectors-lib.sh"

out="$WAYBAR_HOME/theme/drawers.generated.css"
mkdir -p "$WAYBAR_HOME/theme"

shells="$(waybar_css_drawer_group_shell_ids | waybar_css_emit_selector_list)"
shell_children="$(waybar_css_drawer_group_shell_ids | waybar_css_emit_selector_list ' > *')"
handles="$(waybar_css_drawer_handle_ids | waybar_css_emit_selector_list)"
# Prefer "#group > .drawer-child.hidden" plus global ".drawer-child.hidden"
hide_groups="$(waybar_css_drawer_child_hide_group_ids | waybar_css_emit_selector_list ' > .drawer-child.hidden')"

cat >"$out" <<EOF
/* Generated drawer layout — do not edit by hand */
/* SoT: scripts/lib/css-selectors-lib.sh (drawer sides / groups) */
/* Colors: theme/semantic-colors.generated.css */

/* Drawer groups — no container pill; modules keep their own styling */
${shells} {
    background: transparent;
    border: none;
    box-shadow: none;
    padding: 0;
    margin: 4px 2px;
}

${shell_children} {
    margin-top: 0;
    margin-bottom: 0;
}

${handles} {
    font-weight: 700;
    min-width: 24px;
    padding: 0 12px;
    margin: 0;
    background: transparent;
    border: none;
    box-shadow: none;
}

.drawer-child.hidden,
${hide_groups} {
    min-width: 0;
    min-height: 0;
    padding: 0;
    margin: 0;
    border: none;
    background: transparent;
    box-shadow: none;
    opacity: 0;
}
EOF
