#!/usr/bin/env bash
# Generate dock-windows slot modules + group (workspace-switcher pattern).
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
settings="$WAYBAR_HOME/data/waybar-settings.json"
scripts='$WAYBAR_HOME/scripts'

[ -f "$settings" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 1

mod_dir="$WAYBAR_HOME/modules"
mkdir -p "$mod_dir"

slot_count="$(jq -r '.dock_windows.slot_count // 12' "$settings" 2>/dev/null || echo 12)"
if [ "$slot_count" -lt 1 ] 2>/dev/null; then
  slot_count=12
fi
if [ "$slot_count" -gt 16 ] 2>/dev/null; then
  slot_count=16
fi

sig="$(jq -r '.signals.dock_windows // 11' "$settings" 2>/dev/null || echo 11)"
iv="$(jq -r '.module_intervals.dock_windows // .poll_intervals.dock_windows // "once"' "$settings" 2>/dev/null || echo once)"

jq -n --arg scripts "$scripts" --argjson count "$slot_count" --argjson sig "$sig" --arg iv "$iv" '
  def slot($i):
    {
      ("custom/dock-win-" + ($i|tostring)): {
        format: "{text}",
        "return-type": "json",
        signal: $sig,
        interval: (if $iv == "once" then "once" else ($iv|tonumber? // 1) end),
        "hide-empty-text": true,
        "exec-on-event": true,
        exec: ($scripts + "/dock/dock-windows-slot-status.sh " + ($i|tostring) + " \"$WAYBAR_OUTPUT_NAME\""),
        "on-click": ($scripts + "/dock/dock-windows-click.sh focus " + ($i|tostring) + " \"$WAYBAR_OUTPUT_NAME\""),
        "on-click-right": ($scripts + "/dock/dock-windows-click.sh close " + ($i|tostring) + " \"$WAYBAR_OUTPUT_NAME\""),
        "on-click-middle": ($scripts + "/dock/dock-windows-click.sh cycle \"$WAYBAR_OUTPUT_NAME\""),
        tooltip: true
      }
    };
  reduce range(0; $count) as $i ({}; . + slot($i))
' >"$mod_dir/dock-windows.generated.jsonc"

# Group listing the slots (layout references group/dock-windows).
{
  printf '{\n  "group/dock-windows": {\n'
  printf '    "orientation": "inherit",\n'
  printf '    "modules": [\n'
  i=0
  while [ "$i" -lt "$slot_count" ]; do
    if [ "$i" -gt 0 ]; then
      printf ',\n'
    fi
    printf '      "custom/dock-win-%s"' "$i"
    i=$((i + 1))
  done
  printf '\n    ]\n  }\n}\n'
} >"$mod_dir/groups-dock-windows.generated.jsonc"
