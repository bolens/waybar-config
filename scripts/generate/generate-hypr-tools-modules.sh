#!/usr/bin/env bash
# Domain module emitter (split from former generate-module-configs.sh).
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
settings="$WAYBAR_HOME/data/waybar-settings.json"
# Keep literal $WAYBAR_HOME so generated modules stay portable (match other generators).
scripts='$WAYBAR_HOME/scripts'

[ -f "$settings" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 1

mod_dir="$WAYBAR_HOME/modules"
theme_dir="$WAYBAR_HOME/theme"
mkdir -p "$mod_dir" "$theme_dir"

jq -n --slurpfile s "$settings" --arg scripts "$scripts" '
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 0);

  {
    "custom/hyprnotify": {
      format: "{}",
      "return-type": "json",
      interval: iv("hypr_tools"),
      exec: ($scripts + "/services/hypr/hypr-bar-module-status.sh notify"),
      tooltip: false,
      "on-click": ($s[0].hypr_tools.hyprnotify_click // "hyprnotify show")
    },
    "custom/hyprlight": {
      format: "{}",
      "return-type": "json",
      interval: iv("hypr_tools"),
      exec: ($scripts + "/services/hypr/hypr-bar-module-status.sh light"),
      tooltip: false,
      "on-click": ($s[0].hypr_tools.hyprlight_click // "hyprlight osd")
    },
    "custom/hyprwhspr": {
      format: "{}",
      exec: ("sh " + $scripts + "/services/hypr/hyprwhspr-status-wrapper.sh"),
      interval: iv("hyprwhspr"),
      "return-type": "json",
      "exec-on-event": false,
      "on-click": ($s[0].hypr_tools.hyprwhspr_record // "/usr/lib/hyprwhspr/config/hyprland/hyprwhspr-tray.sh record"),
      "on-click-right": ($s[0].hypr_tools.hyprwhspr_restart // "/usr/lib/hyprwhspr/config/hyprland/hyprwhspr-tray.sh restart"),
      tooltip: true
    }
  }
' | jq '.' >"$mod_dir/hypr-tools.generated.jsonc"
