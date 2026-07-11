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
    "custom/keyboard-layout": {
      format: "{}",
      "return-type": "json",
      signal: sig("keyboard_layout"),
      interval: iv("keyboard_layout"),
      exec: ($scripts + "/system/keyboard-layout-status.sh"),
      "on-click": ($s[0].keyboard.on_click // ($scripts + "/system/keyboard-layout-click.sh next")),
      "on-click-right": ($s[0].keyboard.on_click_right // ($scripts + "/system/keyboard-layout-click.sh prev")),
      "on-click-middle": $s[0].keyboard.on_click_middle,
      "on-scroll-up": ($s[0].keyboard.on_scroll_up // ($scripts + "/system/keyboard-layout-click.sh prev")),
      "on-scroll-down": ($s[0].keyboard.on_scroll_down // ($scripts + "/system/keyboard-layout-click.sh next")),
      tooltip: true
    },
    "custom/gamemode": {
      format: "{}",
      "return-type": "json",
      signal: sig("gamemode"),
      interval: iv("gamemode"),
      exec: ($scripts + "/system/gamemode-status.sh"),
      "on-click": ($s[0].gamemode.on_click // ($scripts + "/system/gamemode-click.sh toggle")),
      "on-click-right": ($s[0].gamemode.on_click_right // ($scripts + "/system/gamemode-click.sh restore")),
      "on-click-middle": $s[0].gamemode.on_click_middle,
      tooltip: true
    },
    "custom/keybindhint": {
      format: "{}",
      "return-type": "json",
      interval: "once",
      exec: ($scripts + "/workspaces/keybindhint-status.sh"),
      "on-click": ($scripts + "/workspaces/keybindhint-click.sh"),
      tooltip: true
    }
  } | walk(if type == "object" then with_entries(select(.value != null)) else . end)
' | jq '.' >"$mod_dir/center-extras.generated.jsonc"
