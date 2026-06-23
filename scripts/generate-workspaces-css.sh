#!/usr/bin/env bash
# Generate workspace strip layout from data/workspace-bar.json
# Uses per-slot active backgrounds (standard Waybar pattern) — no overlay pill module.
set -euo pipefail

WAYBAR_HOME="${WAYBAR_HOME:-$HOME/.config/waybar}"
. "${0%/*}/waybar-settings.sh"
config="${WAYBAR_HOME}/data/workspace-bar.json"
settings="${WAYBAR_HOME}/data/waybar-settings.json"
out="$WAYBAR_HOME/theme/workspaces.generated.css"

read_config() {
  local key="$1"
  local default="$2"
  if [[ -f "$config" ]]; then
    jq -r --arg key "$key" --arg default "$default" '.[$key] // $default' "$config"
  else
    printf '%s' "$default"
  fi
}

bar_spacing="6"
if [[ -f "$settings" ]]; then
  bar_spacing="$(jq -r '.bars.spacing // 6' "$settings" 2>/dev/null || echo 6)"
fi

slot_width="$(read_config slot_width 44)"
slot_gap="$(read_config slot_gap 10)"
glyph_width="$(read_config glyph_width "$slot_width")"
glyph_gap="$(read_config glyph_gap "$slot_gap")"
pill_width="$(read_config pill_width "$glyph_width")"
padding_h="$(read_config padding_h 10)"
padding_v="$(read_config padding_v 4)"
font_size="$(read_config font_size 16)"
border_radius="$(read_config border_radius 8)"
glyph_offset="$(read_config glyph_offset 0)"
bar_spacing_override="$(read_config bar_spacing "")"
workspace_active="$(jq -r '.theme.colors.workspace_active // "rgba(255, 42, 127, 0.32)"' "$settings" 2>/dev/null || echo 'rgba(255, 42, 127, 0.32)')"

if [[ -n "$bar_spacing_override" && "$bar_spacing_override" != "null" ]]; then
  bar_spacing="$bar_spacing_override"
fi

# Waybar inserts `spacing` px between every module in a group; cancel it in CSS.
slot_margin=$((glyph_gap - bar_spacing))
glyph_pad=$(( (glyph_width - font_size) / 2 ))
if [[ "$glyph_pad" -lt 0 ]]; then
  glyph_pad=0
fi

{
  cat <<EOF
/* Generated from data/workspace-bar.json — do not edit by hand */
/* Per-slot active pill (like #workspaces button.active). No overlay module. */

#desk-hypr {
    padding: ${padding_v}px ${padding_h}px;
}

#custom-ws-0.ws-hit,
#custom-ws-1.ws-hit,
#custom-ws-2.ws-hit,
#custom-ws-3.ws-hit,
#custom-ws-4.ws-hit,
#custom-ws-5.ws-hit,
#custom-ws-6.ws-hit,
#custom-ws-7.ws-hit,
#custom-ws-8.ws-hit,
#custom-ws-9.ws-hit {
    min-width: ${glyph_width}px;
    padding: 0 ${glyph_pad}px;
    border-radius: ${border_radius}px;
}

#custom-ws-0.ws-hit label,
#custom-ws-1.ws-hit label,
#custom-ws-2.ws-hit label,
#custom-ws-3.ws-hit label,
#custom-ws-4.ws-hit label,
#custom-ws-5.ws-hit label,
#custom-ws-6.ws-hit label,
#custom-ws-7.ws-hit label,
#custom-ws-8.ws-hit label,
#custom-ws-9.ws-hit label {
    font-size: ${font_size}px;
}

#custom-ws-0.ws-hit:not(.hidden) {
    margin-left: ${glyph_offset}px;
}

#custom-ws-1.ws-hit:not(.hidden),
#custom-ws-2.ws-hit:not(.hidden),
#custom-ws-3.ws-hit:not(.hidden),
#custom-ws-4.ws-hit:not(.hidden),
#custom-ws-5.ws-hit:not(.hidden),
#custom-ws-6.ws-hit:not(.hidden),
#custom-ws-7.ws-hit:not(.hidden),
#custom-ws-8.ws-hit:not(.hidden),
#custom-ws-9.ws-hit:not(.hidden) {
    margin-left: ${slot_margin}px;
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
    padding: 0 ${glyph_pad}px;
    background-color: transparent;
    background-image: linear-gradient(90deg, ${workspace_active} 0%, ${workspace_active} 100%);
    background-size: ${pill_width}px 100%;
    background-position: center;
    background-repeat: no-repeat;
}

EOF
} >"$out"
