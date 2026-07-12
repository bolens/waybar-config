#!/usr/bin/env bash
# Emit theme/tokens.generated.css from settings theme (+ bars chrome overrides).
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
settings="$WAYBAR_HOME/data/waybar-settings.json"

[ -f "$settings" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 1

theme_dir="$WAYBAR_HOME/theme"
mkdir -p "$theme_dir"

wall_stub="$theme_dir/tokens.wallpaper.generated.css"
if [ ! -f "$wall_stub" ]; then
  printf '%s\n' '/* Wallpaper overlay — written by theme-apply-wallpaper.sh; do not edit by hand */' >"$wall_stub"
fi

mode="$(jq -r '.theme.mode // "static"' "$settings")"
# Unknown modes fail soft → static (no preset merge, no wallpaper import).
case "$mode" in
  static | wallpaper | preset) ;;
  *) mode="static" ;;
esac
colors_json="$(jq -c '.theme.colors // {}' "$settings")"

if [ "$mode" = "preset" ]; then
  preset_name="$(jq -r '.theme.preset // "cyberpunk"' "$settings")"
  for cand in \
    "$WAYBAR_HOME/data/themes/${preset_name}.jsonc" \
    "$WAYBAR_HOME/data/themes/${preset_name}.json"; do
    if [ -f "$cand" ]; then
      # Strip // comments for jsonc, then merge: preset base, settings colors override.
      preset_colors="$(
        sed -E 's://.*$::g' "$cand" | jq -c '.colors // .' 2>/dev/null || true
      )"
      if [ -n "$preset_colors" ] && [ "$preset_colors" != "null" ]; then
        colors_json="$(jq -cn --argjson p "$preset_colors" --argjson o "$colors_json" '$p + $o')"
      fi
      break
    fi
  done
fi

jq -n --slurpfile s "$settings" --argjson colors "$colors_json" --arg mode "$mode" '
  ($s[0].theme // {}) as $t
  | ($s[0].bars // {}) as $b
  | $colors as $c
  | ($t.font_family // "JetBrainsMono Nerd Font") as $font
  | ($t.font_size // 13) as $size
  | ($t.tooltip_font_size // 12) as $tsize
  | ($b.chrome_radius // $t.border_radius // 8) as $radius
  | ($t.tooltip_padding // "8px 10px") as $tpad
  | ($b.floating == true) as $float
  | ($b.glass_opacity) as $glass
  | ($c.background // "rgba(6, 7, 14, 0.92)") as $bg_raw
  | (if ($glass != null) and (($bg_raw | type) == "string") and ($bg_raw | test("^rgba\\(")) then
      ($bg_raw | capture("rgba\\((?<r>[^,]+),(?<g>[^,]+),(?<b>[^,]+),[^)]+\\)") ) as $m
      | "rgba(" + ($m.r|tostring|gsub("^ +| +$";"")) + ", "
        + ($m.g|tostring|gsub("^ +| +$";"")) + ", "
        + ($m.b|tostring|gsub("^ +| +$";"")) + ", "
        + ($glass|tostring) + ")"
    else $bg_raw end) as $bg
  | ($c.border // "rgba(0, 229, 255, 0.25)") as $border
  | ($c.foreground // "#c8f6ff") as $fg
  | "/* Generated from data/waybar-settings.json theme — do not edit by hand */\n\n"
    + "* {\n"
    + "    font-family: \"" + $font + "\", monospace;\n"
    + "    font-size: " + ($size | tostring) + "px;\n"
    + "    min-height: 0;\n"
    + "}\n\n"
    + "window#waybar {\n"
    + "    background: " + $bg + ";\n"
    + (if $float then
        "    border: 1px solid " + $border + ";\n"
        + "    border-radius: " + ($radius | tostring) + "px;\n"
      else
        "    border-bottom: 1px solid " + $border + ";\n"
      end)
    + "    color: " + $fg + ";\n"
    + "}\n\n"
    + "window#waybar.bottom {\n"
    + (if $float then
        "    border: 1px solid " + $border + ";\n"
      else
        "    border-bottom: none;\n"
        + "    border-top: 1px solid " + $border + ";\n"
      end)
    + "}\n\n"
    + "tooltip, #tooltip {\n"
    + "    background: " + ($c.tooltip_background // "#06070e") + ";\n"
    + "    border: 1px solid " + ($c.tooltip_border // "#005c66") + ";\n"
    + "    border-radius: " + ($radius | tostring) + "px;\n"
    + "}\n\n"
    + "tooltip label, #tooltip label {\n"
    + "    color: " + $fg + ";\n"
    + "    background: transparent;\n"
    + "    padding: " + $tpad + ";\n"
    + "    font-family: \"" + $font + "\", monospace;\n"
    + "    font-size: " + ($tsize | tostring) + "px;\n"
    + "}\n"
    + (if $mode == "wallpaper" then "\n@import \"tokens.wallpaper.generated.css\";\n" else "" end)
' -r >"$theme_dir/tokens.generated.css"
