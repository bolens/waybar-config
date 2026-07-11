#!/usr/bin/env bash
# Generate compositor-specific Hyprland native modules, desk-hypr group, top-left layout,
# and workspace slot modules from workspaces.slot_count.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="$WAYBAR_HOME/scripts"
native_out="$WAYBAR_HOME/modules/hyprland.native.generated.jsonc"
group_out="$WAYBAR_HOME/modules/groups-desk-hypr.generated.jsonc"
top_left_out="$WAYBAR_HOME/layouts/top-left.generated.jsonc"
workspaces_out="$WAYBAR_HOME/modules/workspaces.generated.jsonc"
source_modules="$WAYBAR_HOME/modules/hyprland.jsonc"
desktops_file="$WAYBAR_HOME/data/workspace-desktops.json"
settings="$WAYBAR_HOME/data/waybar-settings.json"

# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

comp="$(detect_compositor)"

workspace_slot_count() {
  local count="0"
  if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
    count="$(jq -r '.workspaces.slot_count // 0' "$settings" 2>/dev/null)"
  fi
  if [ "$count" -lt 1 ] 2>/dev/null; then
    if [ -f "$desktops_file" ]; then
      count="$(jq 'length' "$desktops_file" 2>/dev/null || echo 0)"
    fi
  fi
  if [ "$count" -lt 1 ] 2>/dev/null; then
    count="$("$WAYBAR_SCRIPTS/workspaces/workspaces-query.py" 2>/dev/null | jq '.desktops | length' || echo 0)"
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

generate_workspace_module_defs() {
  local count="$1"
  local scripts='$WAYBAR_HOME/scripts'
  local sig
  sig="$(jq -r '.signals.workspaces // 16' "$settings" 2>/dev/null || echo 16)"

  jq -n --arg scripts "$scripts" --argjson count "$count" --argjson sig "$sig" '
    def slot($i):
      {
        ("custom/ws-" + ($i|tostring)): {
          format: "{text}",
          "return-type": "json",
          signal: $sig,
          interval: "once",
          "hide-empty-text": true,
          "exec-on-event": true,
          exec: ($scripts + "/workspaces/workspaces-slot-status.sh " + ($i|tostring) + " \"$WAYBAR_OUTPUT_NAME\""),
          "on-click": ($scripts + "/workspaces/workspaces-click.sh " + ($i|tostring) + " \"$WAYBAR_OUTPUT_NAME\""),
          "on-scroll-up": ($scripts + "/workspaces/workspaces-click.sh scroll-up \"$WAYBAR_OUTPUT_NAME\""),
          "on-scroll-down": ($scripts + "/workspaces/workspaces-click.sh scroll-down \"$WAYBAR_OUTPUT_NAME\""),
          tooltip: true
        }
      };
    reduce range(0; $count) as $i
      (
        {
          "custom/workspaces": {
            format: "{text}",
            "return-type": "json",
            signal: $sig,
            interval: "once",
            "hide-empty-text": true,
            "exec-on-event": true,
            exec: ($scripts + "/workspaces/workspaces-status.sh \"$WAYBAR_OUTPUT_NAME\""),
            "on-scroll-up": ($scripts + "/workspaces/workspaces-click.sh scroll-up \"$WAYBAR_OUTPUT_NAME\""),
            "on-scroll-down": ($scripts + "/workspaces/workspaces-click.sh scroll-down \"$WAYBAR_OUTPUT_NAME\""),
            tooltip: true
          }
        };
        . + slot($i)
      )
  ' >"$workspaces_out"
}

slot_count="$(workspace_slot_count)"
workspace_modules="$(build_workspace_modules "$slot_count")"
generate_workspace_module_defs "$slot_count"

hypr_tail='[
      "hyprland/submap",
      "custom/hyprlight",
      "custom/hyprwhspr"
    ]'

if [ "$comp" = "hyprland" ]; then
  # Optional native overlay (hyprland/* modules). Missing file must not wipe desk slots.
  if [ -f "$source_modules" ]; then
    cp "$source_modules" "$native_out"
  else
    printf '{}\n' >"$native_out"
  fi
  modules_json="$(
    jq -cn \
      --argjson slots "$workspace_modules" \
      --argjson tail "$hypr_tail" \
      '$slots + $tail'
  )"
else
  # kde and unknown (CI / headless): workspace slots only — never wipe desk modules.
  printf '{}\n' >"$native_out"
  modules_json="$workspace_modules"
fi

top_left_modules='[
    "group/desk-controls",
    "group/media",
    "group/net"
  ]'

if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
  user_left="$(jq -c '.layouts.top.modules_left' "$settings" 2>/dev/null)"
  if [ -n "$user_left" ] && [ "$user_left" != "null" ]; then
    top_left_modules="$user_left"
  fi
fi

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
