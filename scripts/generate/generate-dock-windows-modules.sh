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
  def iv($k): ($s[0].module_intervals[$k] // $s[0].poll_intervals[$k] // 1);
  def sig($k): ($s[0].signals[$k] // null);

  {
    "custom/dock-windows": {
      format: "{}",
      "return-type": "json",
      "min-length": ($s[0].dock_windows.min_length // 64),
      "max-length": ($s[0].dock_windows.max_length // 160),
      expand: (if $s[0].dock_windows.expand != null then $s[0].dock_windows.expand else true end),
      align: ($s[0].dock_windows.align // 0.5),
      signal: sig("dock_windows"),
      interval: iv("dock_windows"),
      exec: ($scripts + "/dock/dock-windows-status.sh"),
      "on-click": ($scripts + "/dock/dock-windows-click.sh activate"),
      "on-click-right": ($scripts + "/dock/dock-windows-click.sh close-focused"),
      "on-click-middle": ($scripts + "/dock/dock-windows-click.sh cycle"),
      tooltip: true
    }
  } | walk(if type == "object" then with_entries(select(.value != null)) else . end)
' | jq '.' >"$mod_dir/dock-windows.generated.jsonc"
