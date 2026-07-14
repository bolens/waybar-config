#!/usr/bin/env bash
# Emit theme/tokens.generated.css from settings theme (+ bars chrome overrides).
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
. "$WAYBAR_SCRIPTS/lib/theme-colors-lib.sh"
. "$WAYBAR_SCRIPTS/lib/css-selectors-lib.sh"
settings="$WAYBAR_HOME/data/waybar-settings.json"

[ -f "$settings" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 1

theme_dir="$WAYBAR_HOME/theme"
mkdir -p "$theme_dir"

wall_stub="$theme_dir/tokens.wallpaper.generated.css"
if [ ! -f "$wall_stub" ]; then
  printf '%s\n' '/* Wallpaper overlay — written by theme-apply-wallpaper.sh; do not edit by hand */' >"$wall_stub"
fi

# Unknown modes fail soft → static (no preset merge, no wallpaper import).
mode="$(waybar_theme_resolve_mode "$settings")"
colors_json="$(waybar_theme_resolve_colors "$settings")"
color_rgb_csv() { waybar_theme_color_rgb_csv "$@"; }
color_with_alpha() { waybar_theme_color_with_alpha "$@"; }

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
# Shared module / drawer chrome (hand CSS owns layout; this owns theme-aware color).
pill_bg="$(color_with_alpha "$accent" "0.06")"
pill_border="$(color_with_alpha "$accent" "0.12")"
pill_hover_bg="$(color_with_alpha "$accent" "0.12")"
pill_hover_border="$(color_with_alpha "$accent" "0.4")"
pill_hover_glow="$(color_with_alpha "$accent" "0.22")"
group_bg="$(color_with_alpha "$accent" "0.04")"
group_border="$(color_with_alpha "$accent" "0.16")"
drawer_glow="$(color_with_alpha "$accent" "0.35")"
drawer_hover_glow="$(color_with_alpha "$accent" "0.45")"
power_glow="$(color_with_alpha "$critical" "0.35")"
power_hover_glow="$(color_with_alpha "$critical" "0.5")"
power_hover_bg="$(color_with_alpha "$critical" "0.14")"
warning_glow="$(color_with_alpha "$warning" "0.35")"
warning_hover_bg="$(color_with_alpha "$warning" "0.14")"
warning_hover_border="$(color_with_alpha "$warning" "0.45")"
# Fixed secondary accents for power-menu specialty (not in theme.colors).
power_logout="#e0aaff"
power_logout_bg="$(color_with_alpha "$power_logout" "0.14")"
power_logout_border="$(color_with_alpha "$power_logout" "0.45")"
power_logout_glow="$(color_with_alpha "$power_logout" "0.35")"
power_suspend="#2cffb0"
power_suspend_bg="$(color_with_alpha "$power_suspend" "0.14")"
power_suspend_border="$(color_with_alpha "$power_suspend" "0.45")"
power_suspend_glow="$(color_with_alpha "$power_suspend" "0.35")"
accent_hover_fg="$fg"
# Soft lighten for drawer hover when fg matches cyberpunk default.
if [[ "$(printf '%s' "$fg" | tr '[:upper:]' '[:lower:]')" == "#c8f6ff" ]]; then
  accent_hover_fg="#c8f6ff"
fi

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

# Shared pill layout (SoT: scripts/lib/css-selectors-lib.sh → waybar_css_pill_ids).
{
  printf '%s\n' '/* Generated shared pill layout — do not edit by hand */' ''
  waybar_css_pill_ids | waybar_css_emit_selector_list
  cat <<'EOF'
 {
    padding: 0 10px;
    margin: 0 2px;
    border-radius: 6px;
    transition: background-color 120ms ease, border-color 120ms ease, box-shadow 120ms ease, color 120ms ease;
}
EOF
} >"$theme_dir/module-pills.generated.css"

ws_slots="$(waybar_css_slot_count "$settings" workspaces 5 1 10)"
dock_slots="$(waybar_css_slot_count "$settings" dock_windows 12 1 16)"
pill_sels="$(waybar_css_pill_ids | waybar_css_emit_selector_list)"
pill_hover_sels="$(waybar_css_pill_hover_ids | waybar_css_emit_selector_list ':hover')"
cluster_sels="$(waybar_css_cluster_group_ids | waybar_css_emit_selector_list)"
drawer_accent_sels="$(waybar_css_drawer_accent_handle_ids | waybar_css_emit_selector_list)"
drawer_accent_hover_sels="$(waybar_css_drawer_accent_handle_ids | waybar_css_emit_selector_list ':hover')"
dock_inactive_sels="$(waybar_css_id_range '#custom-dock-win-' "$dock_slots" '.dock-win-inactive:not(.appicon)')"
dock_active_sels="$(waybar_css_id_range '#custom-dock-win-' "$dock_slots" '.dock-win-active:not(.appicon)')"
dock_hit_hover_sels="$(waybar_css_id_range '#custom-dock-win-' "$dock_slots" '.dock-win-hit:not(.appicon):hover')"
dock_active_hover_sels="$(waybar_css_id_range '#custom-dock-win-' "$dock_slots" '.dock-win-active:not(.appicon):hover')"
ws_inactive_sels="$(waybar_css_id_range '#custom-ws-' "$ws_slots" '.ws-inactive')"
ws_active_sels="$(waybar_css_id_range '#custom-ws-' "$ws_slots" '.ws-active')"
ws_active_label_sels="$(waybar_css_id_range '#custom-ws-' "$ws_slots" '.ws-active label')"
ws_inactive_hover_sels="$(waybar_css_id_range '#custom-ws-' "$ws_slots" '.ws-inactive:hover')"
ws_active_hover_sels="$(waybar_css_id_range '#custom-ws-' "$ws_slots" '.ws-active:hover')"

# GTK3 cannot use var()/ :root — bake semantic colors as concrete rules (override static CSS).
# Pill ID list SoT: css-selectors-lib.sh; layout chrome: module-pills.generated.css + modules.css.
cat >"$theme_dir/semantic-colors.generated.css" <<EOF
/* Generated theme semantic colors — do not edit by hand */

/* --- Group chrome (non-drawer clusters) --- */
${cluster_sels} {
    background: ${group_bg};
    border: 1px solid ${group_border};
}

/* --- Module pill chrome (accent-tinted; follows theme.mode / presets) --- */
${pill_sels} {
    background-color: ${pill_bg};
    border: 1px solid ${pill_border};
}

${pill_hover_sels} {
    background-color: ${pill_hover_bg};
    border-color: ${pill_hover_border};
    box-shadow: 0 0 10px ${pill_hover_glow};
}

/* --- Drawer handles --- */
${drawer_accent_sels} {
    color: ${accent};
    text-shadow: 0 0 6px ${drawer_glow};
}

${drawer_accent_hover_sels} {
    color: ${accent_hover_fg};
    text-shadow: 0 0 8px ${drawer_hover_glow};
    background: ${accent_hover_bg};
}

#custom-power-drawer {
    color: ${critical};
    text-shadow: 0 0 6px ${power_glow};
}

#custom-power-drawer:hover {
    color: ${critical_hover};
    text-shadow: 0 0 8px ${power_hover_glow};
    background: ${power_hover_bg};
}

/* Power action specialty hovers (warning / accent / critical + fixed secondary accents) */
#custom-lock:hover {
    color: ${warning};
    background: ${warning_hover_bg};
    border-color: ${warning_hover_border};
    box-shadow: 0 0 10px ${warning_glow};
    text-shadow: 0 0 8px ${warning_glow};
}

#custom-logout:hover {
    color: ${power_logout};
    background: ${power_logout_bg};
    border-color: ${power_logout_border};
    box-shadow: 0 0 10px ${power_logout_glow};
    text-shadow: 0 0 8px ${power_logout_glow};
}

#custom-suspend:hover {
    color: ${power_suspend};
    background: ${power_suspend_bg};
    border-color: ${power_suspend_border};
    box-shadow: 0 0 10px ${power_suspend_glow};
    text-shadow: 0 0 8px ${power_suspend_glow};
}

#custom-reboot:hover {
    color: ${accent};
    background: ${pill_hover_bg};
    border-color: ${pill_hover_border};
    box-shadow: 0 0 10px ${pill_hover_glow};
    text-shadow: 0 0 8px ${drawer_hover_glow};
}

#custom-shutdown:hover {
    color: ${critical};
    background: ${power_hover_bg};
    border-color: ${critical_border};
    box-shadow: 0 0 10px ${critical_glow};
    text-shadow: 0 0 8px ${critical_active_glow};
}

#custom-power-menu:hover {
    color: ${critical};
    background: ${power_hover_bg};
    border-color: ${critical_border};
    box-shadow: 0 0 10px ${critical_glow};
    text-shadow: 0 0 8px ${critical_active_glow};
}

/* --- Threshold / status classes --- */
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
#custom-docker.warning,
#custom-syncthing.warning,
#custom-sunshine.warning,
#custom-streamdeck.warning,
#custom-i2pd.warning,
#custom-yggdrasil.warning,
#custom-ipfs.warning,
#custom-runtimes.warning,
#custom-powerprofiles.warning,
#custom-asusctl.warning,
#custom-brightness.warning,
#custom-tailscale.warning,
#custom-libredefender.warning,
#custom-chkrootkit.warning,
#custom-hyprwhspr.warning,
#custom-pomodoro.work {
    color: ${warning};
    border-color: ${warning_border};
    background: ${warning_bg};
    text-shadow: 0 0 6px ${warning};
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
#custom-systemd.critical,
#custom-docker.critical,
#custom-syncthing.critical,
#custom-sunshine.critical,
#custom-streamdeck.critical,
#custom-i2pd.critical,
#custom-yggdrasil.critical,
#custom-ipfs.critical,
#custom-runtimes.critical,
#custom-powerprofiles.critical,
#custom-brightness.critical,
#custom-tailscale.critical,
#custom-libredefender.critical,
#custom-chkrootkit.critical {
    color: ${critical};
    border-color: ${critical_border};
    background: ${critical_bg};
    box-shadow: 0 0 8px ${critical_glow};
    text-shadow: 0 0 8px ${critical};
}

#custom-pomodoro.break {
    color: ${accent};
    border-color: ${accent_dim};
}

${dock_inactive_sels} {
    color: ${accent_dim};
}

${dock_active_sels} {
    color: ${critical};
    background-color: ${critical_active_bg};
    text-shadow: 0 0 8px ${critical_active_glow};
}

${dock_hit_hover_sels} {
    color: ${accent};
    background-color: ${accent_hover_bg};
}

${dock_active_hover_sels} {
    color: ${critical_hover};
    background-color: ${critical_hover_bg};
}

${ws_inactive_sels} {
    color: ${accent_dim};
}

${ws_active_sels} {
    color: ${critical};
}

${ws_active_label_sels} {
    text-shadow: 0 0 8px ${critical_active_glow};
}

${ws_inactive_hover_sels} {
    color: ${accent};
    background-color: ${accent_hover_bg};
}

${ws_active_hover_sels} {
    color: ${critical_hover};
}
EOF
