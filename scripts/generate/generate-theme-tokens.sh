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

jq -n --slurpfile s "$settings" '
  ($s[0].theme // {}) as $t
  | ($t.colors // {}) as $c
  | ($t.font_family // "JetBrainsMono Nerd Font") as $font
  | ($t.font_size // 13) as $size
  | ($t.tooltip_font_size // 12) as $tsize
  | ($t.border_radius // 8) as $radius
  | ($t.tooltip_padding // "8px 10px") as $tpad
  | "/* Generated from data/waybar-settings.json theme — do not edit by hand */\n\n"
    + "* {\n"
    + "    font-family: \"" + $font + "\", monospace;\n"
    + "    font-size: " + ($size | tostring) + "px;\n"
    + "    min-height: 0;\n"
    + "}\n\n"
    + "window#waybar {\n"
    + "    background: " + ($c.background // "rgba(6, 7, 14, 0.92)") + ";\n"
    + "    border-bottom: 1px solid " + ($c.border // "rgba(0, 229, 255, 0.25)") + ";\n"
    + "    color: " + ($c.foreground // "#c8f6ff") + ";\n"
    + "}\n\n"
    + "window#waybar.bottom {\n"
    + "    border-bottom: none;\n"
    + "    border-top: 1px solid " + ($c.border // "rgba(0, 229, 255, 0.25)") + ";\n"
    + "}\n\n"
    + "tooltip, #tooltip {\n"
    + "    background: " + ($c.tooltip_background // "#06070e") + ";\n"
    + "    border: 1px solid " + ($c.tooltip_border // "#005c66") + ";\n"
    + "    border-radius: " + ($radius | tostring) + "px;\n"
    + "}\n\n"
    + "tooltip label, #tooltip label {\n"
    + "    color: " + ($c.foreground // "#c8f6ff") + ";\n"
    + "    background: transparent;\n"
    + "    padding: " + $tpad + ";\n"
    + "    font-family: \"" + $font + "\", monospace;\n"
    + "    font-size: " + ($tsize | tostring) + "px;\n"
    + "}\n"
' -r >"$theme_dir/tokens.generated.css"
