#!/usr/bin/env bash
# Regenerate dock launcher modules and dock drawer group from data/dock-apps.json.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
manifest="$WAYBAR_HOME/data/dock-apps.json"
settings="$WAYBAR_HOME/data/waybar-settings.json"
modules_out="$WAYBAR_HOME/modules/dock.generated.jsonc"
groups_out="$WAYBAR_HOME/modules/groups-dock.generated.jsonc"
scripts='$WAYBAR_HOME/scripts'

[ -f "$manifest" ] || exit 0

# IDs enter module names, CSS selectors, icon paths and shell arguments.
# Validate before touching any generated output; process substitution hides jq errors.
if ! jq -e '
  type == "object"
  and all(keys[]; test("^[A-Za-z0-9_-]+$"))
  and all(.[]; type == "object")
' "$manifest" >/dev/null; then
  echo "Invalid dock manifest: expected object entries with IDs using letters, digits, _ or -" >&2
  exit 1
fi

section_order_json='["web","dev","misc"]'
drawer_click='true'
drawer_duration='500'
drawer_class='drawer-child'
drawer_ltr='false'
interval=5
dock_signal=26

if [ -f "$settings" ]; then
  section_order_json="$(jq -c '.dock.section_order // ["web","dev","misc"]' "$settings")"
  drawer_click="$(jq -r 'if .drawers.click_to_reveal != null then .drawers.click_to_reveal else true end' "$settings")"
  drawer_duration="$(jq -r '.drawers.transition_duration // 500' "$settings")"
  drawer_class="$(jq -r '.drawers.children_class // "drawer-child"' "$settings")"
  drawer_ltr="$(jq -r 'if .drawers.left_to_right.right != null then .drawers.left_to_right.right else true end' "$settings")"
  interval="$(jq -r '.module_intervals.dock_apps // 5' "$settings")"
  dock_signal="$(jq -r '.signals.dock_apps // 26' "$settings")"
fi

drawer_class_json="$(jq -cn --arg value "$drawer_class" '$value')"

mapfile -t app_ids < <(
  jq -r \
    --argjson order "$section_order_json" \
    '
      to_entries
      | map(. + {section: (.value.section // "misc")})
      | sort_by(.section as $s | ($order | index($s) // 999), .key)
      | .[].key
    ' "$manifest"
)

{
  printf '{\n'
  for i in "${!app_ids[@]}"; do
    id="${app_ids[$i]}"
    [ "$i" -gt 0 ] && printf ',\n'
    cat <<EOF
  "custom/dock-${id}": {
    "format": "{text}",
    "return-type": "json",
    "interval": "${interval}",
    "signal": ${dock_signal},
    "tooltip": true,
    "escape": true,
    "hide-empty-text": false,
    "exec": "${scripts}/dock/dock-launcher.sh ${id} status",
    "on-click": "${scripts}/dock/dock-launcher.sh ${id} click on-click",
    "on-click-right": "${scripts}/dock/dock-launcher.sh ${id} click on-click-right",
    "on-click-middle": "${scripts}/dock/dock-launcher.sh ${id} click on-click-middle"
  }
EOF
  done
  printf '\n}\n'
} >"$modules_out"

{
  printf '{\n  "group/dock-apps": {\n'
  printf '    "orientation": "inherit",\n'
  printf '    "drawer": {\n'
  printf '      "click-to-reveal": %s,\n' "$drawer_click"
  printf '      "transition-duration": %s,\n' "$drawer_duration"
  printf '      "children-class": %s,\n' "$drawer_class_json"
  printf '      "transition-left-to-right": %s\n' "$drawer_ltr"
  printf '    },\n'
  printf '    "modules": [\n'
  printf '      "custom/dock-drawer"'
  for id in "${app_ids[@]}"; do
    printf ',\n      "custom/dock-%s"' "$id"
  done
  printf '\n    ]\n  }\n}\n'
} >"$groups_out"

printf '[\n  "group/dock-apps"\n]\n' >"$WAYBAR_HOME/layouts/bottom-dock-left.generated.jsonc"
