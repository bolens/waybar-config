#!/usr/bin/env bash
# Generate non-drawer cluster group layout (#center / #status) from SoT.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/css-selectors-lib.sh"

out="$WAYBAR_HOME/theme/groups.generated.css"
mkdir -p "$WAYBAR_HOME/theme"

clusters="$(waybar_css_cluster_group_ids | waybar_css_emit_selector_list)"
cluster_children="$(waybar_css_cluster_group_ids | waybar_css_emit_selector_list ' > *')"
cluster_not_last="$(waybar_css_cluster_group_ids | waybar_css_emit_selector_list ' > *:not(:last-child)')"
cluster_not_first="$(waybar_css_cluster_group_ids | waybar_css_emit_selector_list ' > *:not(:first-child)')"
cluster_first="$(waybar_css_cluster_group_ids | waybar_css_emit_selector_list ' > *:first-child')"
cluster_last="$(waybar_css_cluster_group_ids | waybar_css_emit_selector_list ' > *:last-child')"

cat >"$out" <<EOF
/* Generated cluster group layout — do not edit by hand */
/* SoT: scripts/lib/css-selectors-lib.sh (waybar_css_cluster_group_ids) */
/* Colors: theme/semantic-colors.generated.css */

${clusters} {
    border-radius: 8px;
    padding: 0 2px;
    margin: 4px 2px;
}

${cluster_children} {
    margin-top: 0;
    margin-bottom: 0;
}

${cluster_not_last} {
    margin-right: 0;
    border-top-right-radius: 0;
    border-bottom-right-radius: 0;
    border-right: none;
}

${cluster_not_first} {
    border-top-left-radius: 0;
    border-bottom-left-radius: 0;
}

${cluster_first} {
    border-top-left-radius: 6px;
    border-bottom-left-radius: 6px;
}

${cluster_last} {
    border-top-right-radius: 6px;
    border-bottom-right-radius: 6px;
}
EOF
