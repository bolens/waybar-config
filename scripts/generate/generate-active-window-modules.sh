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
  def per_out:
    (($s[0].active_window // {}).per_output) as $p
    | if $p == false then false else true end;
  def out_arg:
    if per_out then " \"$WAYBAR_OUTPUT_NAME\"" else "" end;

  {
    "custom/active-window": {
      format: "{text}",
      "return-type": "json",
      escape: true,
      exec: ($scripts + "/workspaces/active-window-scroll.sh" + out_arg),
      tooltip: true,
      "on-click": ($scripts + "/workspaces/window-switcher.sh" + out_arg)
    }
  } | walk(if type == "object" then with_entries(select(.value != null)) else . end)
' | jq '.' >"$mod_dir/compositor.generated.jsonc"
