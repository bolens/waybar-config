#!/usr/bin/env bash
# Generate compositor-specific Hyprland native modules, desk-hypr group, and top-left layout.
set -euo pipefail

WAYBAR_HOME="${WAYBAR_HOME:-$HOME/.config/waybar}"
script_dir="$WAYBAR_HOME/scripts"
native_out="$WAYBAR_HOME/modules/hyprland.native.generated.jsonc"
group_out="$WAYBAR_HOME/modules/groups-desk-hypr.generated.jsonc"
top_left_out="$WAYBAR_HOME/layouts/top-left.generated.jsonc"
source_modules="$WAYBAR_HOME/modules/hyprland.jsonc"
desktops_file="$WAYBAR_HOME/data/workspace-desktops.json"

# shellcheck source=compositor-session.sh
. "$script_dir/compositor-session.sh"

comp="$(detect_compositor)"

workspace_slot_count() {
  local count="0"
  if [ -f "$desktops_file" ]; then
    count="$(jq 'length' "$desktops_file" 2>/dev/null || echo 0)"
  fi
  if [ "$count" -lt 1 ] 2>/dev/null; then
    count="$("$script_dir/workspaces-query.py" 2>/dev/null | jq '.desktops | length' || echo 0)"
  fi
  if [ "$count" -lt 1 ] 2>/dev/null; then
    count=5
  fi
  if [ "$count" -gt 10 ] 2>/dev/null; then
    count=10
  fi
  printf '%s' "$count"
}

build_workspace_modules() {
  local count="$1"
  local i
  printf '[\n'
  for ((i = 0; i < count; i++)); do
    if [[ "$i" -gt 0 ]]; then
      printf ',\n'
    fi
    printf '      "custom/ws-%s"' "$i"
  done
  printf '\n    ]'
}

slot_count="$(workspace_slot_count)"
workspace_modules="$(build_workspace_modules "$slot_count")"

hypr_tail='[
      "hyprland/submap",
      "custom/hyprlight",
      "custom/hyprwhspr"
    ]'

if [ "$comp" = "hyprland" ] && [ -f "$source_modules" ]; then
  cp "$source_modules" "$native_out"
  modules_json="$(
    jq -cn \
      --argjson slots "$workspace_modules" \
      --argjson tail "$hypr_tail" \
      '$slots + $tail'
  )"
elif [ "$comp" = "kde" ]; then
  printf '{}\n' >"$native_out"
  modules_json="$workspace_modules"
else
  printf '{}\n' >"$native_out"
  modules_json='[]'
fi

top_left_modules='[
    "group/desk-controls",
    "group/media",
    "group/net"
  ]'

cat >"$group_out" <<EOF
{
  "group/desk-hypr": {
    "orientation": "inherit",
    "modules": $modules_json
  }
}
EOF

cat >"$top_left_out" <<EOF
{
  "modules-left": $top_left_modules
}
EOF
