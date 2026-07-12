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

# hex/rgba → "r, g, b"; empty if unparseable.
color_rgb_csv() {
  local c="$1"
  if [[ "$c" =~ ^#([0-9a-fA-F]{6})$ ]]; then
    local h="${BASH_REMATCH[1]}"
    printf '%d, %d, %d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
  elif [[ "$c" =~ ^#([0-9a-fA-F]{3})$ ]]; then
    local h="${BASH_REMATCH[1]}"
    printf '%d, %d, %d' "0x${h:0:1}${h:0:1}" "0x${h:1:1}${h:1:1}" "0x${h:2:1}${h:2:1}"
  elif [[ "$c" =~ rgba?\(\ *([0-9.]+)\ *,\ *([0-9.]+)\ *,\ *([0-9.]+) ]]; then
    printf '%d, %d, %d' "${BASH_REMATCH[1]%.*}" "${BASH_REMATCH[2]%.*}" "${BASH_REMATCH[3]%.*}"
  else
    printf ''
  fi
}

# Produce rgba(r,g,b,a); if unparseable, echo the solid color as-is.
color_with_alpha() {
  local c="$1" a="$2"
  local rgb
  rgb="$(color_rgb_csv "$c")"
  if [[ -n "$rgb" ]]; then
    printf 'rgba(%s, %s)' "$rgb" "$a"
  else
    printf '%s' "$c"
  fi
}

fg="$(jq -rn --argjson c "$colors_json" '$c.foreground // "#c8f6ff"')"
accent="$(jq -rn --argjson c "$colors_json" '$c.accent // "#00e5ff"')"
warning="$(jq -rn --argjson c "$colors_json" '$c.warning // "#ffe600"')"
critical="$(jq -rn --argjson c "$colors_json" '$c.critical // "#ff2a7f"')"
ws_active="$(jq -rn --argjson c "$colors_json" '$c.workspace_active // "rgba(255, 42, 127, 0.32)"')"
ws_inactive="$(jq -rn --argjson c "$colors_json" '$c.workspace_inactive // empty')"
if [[ -z "$ws_inactive" || "$ws_inactive" == "null" ]]; then
  ws_inactive="$(color_with_alpha "$accent" "0.42")"
fi

crit_lc="$(printf '%s' "$critical" | tr '[:upper:]' '[:lower:]')"
if [[ "$crit_lc" == "#ff2a7f" ]]; then
  critical_hover="#ff5a9a"
else
  critical_hover="$critical"
fi

warning_border="$(color_with_alpha "$warning" "0.45")"
warning_bg="$(color_with_alpha "$warning" "0.08")"
critical_border="$(color_with_alpha "$critical" "0.55")"
critical_bg="$(color_with_alpha "$critical" "0.1")"
critical_glow="$(color_with_alpha "$critical" "0.25")"
accent_dim="$(color_with_alpha "$accent" "0.42")"
accent_hover_bg="$(color_with_alpha "$accent" "0.10")"
critical_active_bg="$(color_with_alpha "$critical" "0.14")"
critical_active_glow="$(color_with_alpha "$critical" "0.55")"
critical_hover_bg="$(color_with_alpha "$critical" "0.18")"
critical_breathe_bg="$(color_with_alpha "$critical" "0.25")"
critical_breathe_glow="$(color_with_alpha "$critical" "0.4")"

jq -n --slurpfile s "$settings" --argjson colors "$colors_json" --arg mode "$mode" \
  --arg fg "$fg" --arg accent "$accent" --arg warning "$warning" --arg critical "$critical" \
  --arg ws_active "$ws_active" --arg ws_inactive "$ws_inactive" \
  --arg warning_border "$warning_border" --arg warning_bg "$warning_bg" \
  --arg critical_border "$critical_border" --arg critical_bg "$critical_bg" \
  --arg critical_glow "$critical_glow" --arg accent_dim "$accent_dim" \
  --arg accent_hover_bg "$accent_hover_bg" --arg critical_hover "$critical_hover" \
  --arg critical_active_bg "$critical_active_bg" --arg critical_active_glow "$critical_active_glow" \
  --arg critical_hover_bg "$critical_hover_bg" \
  --arg critical_breathe_bg "$critical_breathe_bg" --arg critical_breathe_glow "$critical_breathe_glow" '
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
  | "/* Generated from data/waybar-settings.json theme — do not edit by hand */\n"
    + "/* GTK3/Waybar: no CSS custom properties / :root — colors are baked below and in semantic-colors.generated.css */\n\n"
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

# GTK3 cannot use var()/ :root — bake semantic colors as concrete rules (override static CSS).
cat >"$theme_dir/semantic-colors.generated.css" <<EOF
/* Generated theme semantic colors — do not edit by hand */

#custom-cpu.warning,
#custom-gpu.warning,
#custom-memory.warning,
#custom-disk.warning,
#custom-nvme.warning,
#custom-stats-carousel.warning,
#custom-psu.warning,
#custom-fans.warning,
#custom-liquidctl.warning,
#custom-coolercontrol.warning,
#custom-openlinkhub.warning,
#custom-ups.warning,
#custom-updates.warning,
#custom-device-battery.warning,
#custom-homelab.warning,
#custom-github.warning,
#custom-pomodoro.work {
    color: ${warning};
    border-color: ${warning_border};
    background: ${warning_bg};
}

#custom-cpu.critical,
#custom-gpu.critical,
#custom-memory.critical,
#custom-disk.critical,
#custom-nvme.critical,
#custom-psu.critical,
#custom-fans.critical,
#custom-liquidctl.critical,
#custom-coolercontrol.critical,
#custom-openlinkhub.critical,
#custom-stats-carousel.critical,
#custom-ups.critical,
#custom-updates.critical,
#custom-device-battery.critical,
#custom-homelab.critical,
#custom-systemd.critical {
    color: ${critical};
    border-color: ${critical_border};
    background: ${critical_bg};
    box-shadow: 0 0 8px ${critical_glow};
}

#custom-pomodoro.break {
    color: ${accent};
    border-color: ${accent_dim};
}

#custom-dock-win-0.dock-win-inactive,
#custom-dock-win-1.dock-win-inactive,
#custom-dock-win-2.dock-win-inactive,
#custom-dock-win-3.dock-win-inactive,
#custom-dock-win-4.dock-win-inactive,
#custom-dock-win-5.dock-win-inactive,
#custom-dock-win-6.dock-win-inactive,
#custom-dock-win-7.dock-win-inactive,
#custom-dock-win-8.dock-win-inactive,
#custom-dock-win-9.dock-win-inactive,
#custom-dock-win-10.dock-win-inactive,
#custom-dock-win-11.dock-win-inactive,
#custom-dock-win-12.dock-win-inactive,
#custom-dock-win-13.dock-win-inactive,
#custom-dock-win-14.dock-win-inactive,
#custom-dock-win-15.dock-win-inactive {
    color: ${accent_dim};
}

#custom-dock-win-0.dock-win-active,
#custom-dock-win-1.dock-win-active,
#custom-dock-win-2.dock-win-active,
#custom-dock-win-3.dock-win-active,
#custom-dock-win-4.dock-win-active,
#custom-dock-win-5.dock-win-active,
#custom-dock-win-6.dock-win-active,
#custom-dock-win-7.dock-win-active,
#custom-dock-win-8.dock-win-active,
#custom-dock-win-9.dock-win-active,
#custom-dock-win-10.dock-win-active,
#custom-dock-win-11.dock-win-active,
#custom-dock-win-12.dock-win-active,
#custom-dock-win-13.dock-win-active,
#custom-dock-win-14.dock-win-active,
#custom-dock-win-15.dock-win-active {
    color: ${critical};
    background-color: ${critical_active_bg};
    text-shadow: 0 0 8px ${critical_active_glow};
}

#custom-dock-win-0.dock-win-hit:hover,
#custom-dock-win-1.dock-win-hit:hover,
#custom-dock-win-2.dock-win-hit:hover,
#custom-dock-win-3.dock-win-hit:hover,
#custom-dock-win-4.dock-win-hit:hover,
#custom-dock-win-5.dock-win-hit:hover,
#custom-dock-win-6.dock-win-hit:hover,
#custom-dock-win-7.dock-win-hit:hover,
#custom-dock-win-8.dock-win-hit:hover,
#custom-dock-win-9.dock-win-hit:hover,
#custom-dock-win-10.dock-win-hit:hover,
#custom-dock-win-11.dock-win-hit:hover,
#custom-dock-win-12.dock-win-hit:hover,
#custom-dock-win-13.dock-win-hit:hover,
#custom-dock-win-14.dock-win-hit:hover,
#custom-dock-win-15.dock-win-hit:hover {
    color: ${accent};
    background-color: ${accent_hover_bg};
}

#custom-dock-win-0.dock-win-active:hover,
#custom-dock-win-1.dock-win-active:hover,
#custom-dock-win-2.dock-win-active:hover,
#custom-dock-win-3.dock-win-active:hover,
#custom-dock-win-4.dock-win-active:hover,
#custom-dock-win-5.dock-win-active:hover,
#custom-dock-win-6.dock-win-active:hover,
#custom-dock-win-7.dock-win-active:hover,
#custom-dock-win-8.dock-win-active:hover,
#custom-dock-win-9.dock-win-active:hover,
#custom-dock-win-10.dock-win-active:hover,
#custom-dock-win-11.dock-win-active:hover,
#custom-dock-win-12.dock-win-active:hover,
#custom-dock-win-13.dock-win-active:hover,
#custom-dock-win-14.dock-win-active:hover,
#custom-dock-win-15.dock-win-active:hover {
    color: ${critical_hover};
    background-color: ${critical_hover_bg};
}

#custom-ws-0.ws-inactive,
#custom-ws-1.ws-inactive,
#custom-ws-2.ws-inactive,
#custom-ws-3.ws-inactive,
#custom-ws-4.ws-inactive,
#custom-ws-5.ws-inactive,
#custom-ws-6.ws-inactive,
#custom-ws-7.ws-inactive,
#custom-ws-8.ws-inactive,
#custom-ws-9.ws-inactive {
    color: ${accent_dim};
}

#custom-ws-0.ws-active,
#custom-ws-1.ws-active,
#custom-ws-2.ws-active,
#custom-ws-3.ws-active,
#custom-ws-4.ws-active,
#custom-ws-5.ws-active,
#custom-ws-6.ws-active,
#custom-ws-7.ws-active,
#custom-ws-8.ws-active,
#custom-ws-9.ws-active {
    color: ${critical};
}

#custom-ws-0.ws-active label,
#custom-ws-1.ws-active label,
#custom-ws-2.ws-active label,
#custom-ws-3.ws-active label,
#custom-ws-4.ws-active label,
#custom-ws-5.ws-active label,
#custom-ws-6.ws-active label,
#custom-ws-7.ws-active label,
#custom-ws-8.ws-active label,
#custom-ws-9.ws-active label {
    text-shadow: 0 0 8px ${critical_active_glow};
}

#custom-ws-0.ws-inactive:hover,
#custom-ws-1.ws-inactive:hover,
#custom-ws-2.ws-inactive:hover,
#custom-ws-3.ws-inactive:hover,
#custom-ws-4.ws-inactive:hover,
#custom-ws-5.ws-inactive:hover,
#custom-ws-6.ws-inactive:hover,
#custom-ws-7.ws-inactive:hover,
#custom-ws-8.ws-inactive:hover,
#custom-ws-9.ws-inactive:hover {
    color: ${accent};
    background-color: ${accent_hover_bg};
}

#custom-ws-0.ws-active:hover,
#custom-ws-1.ws-active:hover,
#custom-ws-2.ws-active:hover,
#custom-ws-3.ws-active:hover,
#custom-ws-4.ws-active:hover,
#custom-ws-5.ws-active:hover,
#custom-ws-6.ws-active:hover,
#custom-ws-7.ws-active:hover,
#custom-ws-8.ws-active:hover,
#custom-ws-9.ws-active:hover {
    color: ${critical_hover};
}
EOF
