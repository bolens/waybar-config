#!/usr/bin/env bash
# Generate workspace strip layout from data/workspace-bar.json
# Uses per-slot active backgrounds (standard Waybar pattern) — no overlay pill module.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
. "$WAYBAR_SCRIPTS/lib/theme-colors-lib.sh"
. "$WAYBAR_SCRIPTS/lib/settings-bool-lib.sh"
. "$WAYBAR_SCRIPTS/lib/css-selectors-lib.sh"
config="${WAYBAR_HOME}/data/workspace-bar.json"
settings="${WAYBAR_HOME}/data/waybar-settings.json"
out="$WAYBAR_HOME/theme/workspaces.generated.css"

read_config() {
  local key="$1"
  local default="$2"
  if [[ -f "$config" ]]; then
    # Use has() — jq's // treats JSON false as missing.
    jq -r --arg key "$key" --arg default "$default" \
      'if has($key) then (.[$key] | tostring) else $default end' "$config"
  else
    printf '%s' "$default"
  fi
}

bar_spacing="6"
if [[ -f "$settings" ]]; then
  bar_spacing="$(jq -r '.bars.spacing // 6' "$settings" 2>/dev/null || echo 6)"
fi

# workspaces.slot_count: clamp 1–10, default 5 (match compositor modules).
slot_count="$(waybar_css_slot_count "$settings" workspaces 5 1 10)"

fit_content="$(read_config fit_content true)"
slot_width="$(read_config slot_width 44)"
slot_gap="$(read_config slot_gap 10)"
glyph_width="$(read_config glyph_width "$slot_width")"
glyph_gap="$(read_config glyph_gap "$slot_gap")"
pill_width="$(read_config pill_width "$glyph_width")"
padding_h="$(read_config padding_h 10)"
padding_v="$(read_config padding_v 4)"
font_size="$(read_config font_size 16)"
glyph_pad_h="$(read_config glyph_pad_h 6)"
border_radius="$(read_config border_radius 8)"
glyph_offset="$(read_config glyph_offset 0)"
bar_spacing_override="$(read_config bar_spacing "")"
colors_json="{}"
if [[ -f "$settings" ]]; then
  colors_json="$(waybar_theme_resolve_colors "$settings")"
fi
workspace_active="$(waybar_theme_color_get "$colors_json" "workspace_active" "rgba(255, 42, 127, 0.32)")"

if [[ -n "$bar_spacing_override" && "$bar_spacing_override" != "null" ]]; then
  bar_spacing="$bar_spacing_override"
fi

# Waybar inserts `spacing` px between every module in a group; cancel it in CSS.
slot_margin=$((glyph_gap - bar_spacing))

if waybar_is_false "$fit_content"; then
  fit_content=0
  glyph_pad=$(((glyph_width - font_size) / 2))
  if [[ "$glyph_pad" -lt 0 ]]; then
    glyph_pad=0
  fi
else
  fit_content=1
  glyph_pad="$glyph_pad_h"
fi

hit_sels="$(waybar_css_id_range '#custom-ws-' "$slot_count" '.ws-hit')"
label_sels="$(waybar_css_id_range '#custom-ws-' "$slot_count" '.ws-hit label')"
active_sels="$(waybar_css_id_range '#custom-ws-' "$slot_count" '.ws-active')"
inactive_sels="$(waybar_css_id_range '#custom-ws-' "$slot_count" '.ws-inactive')"
inactive_hover_sels="$(waybar_css_id_range '#custom-ws-' "$slot_count" '.ws-inactive:hover')"
hidden_sels="$(waybar_css_id_range '#custom-ws-' "$slot_count" '.hidden')"

{
  cat <<EOF
/* Generated from data/workspace-bar.json — do not edit by hand */
/* Per-slot active pill (like #workspaces button.active). No overlay module. */

#desk-hypr {
    padding: ${padding_v}px ${padding_h}px;
}

${hit_sels} {
    background: transparent;
    background-image: none;
    border: none;
    box-shadow: none;
    margin-top: 0;
    margin-bottom: 0;
    margin-right: 0;
    transition:
        color 280ms cubic-bezier(0.4, 0, 0.2, 1),
        opacity 280ms cubic-bezier(0.4, 0, 0.2, 1),
        background-color 300ms cubic-bezier(0.4, 0, 0.2, 1);
EOF

  if [[ "$fit_content" -eq 1 ]]; then
    cat <<EOF
    min-width: 0;
    padding: 0 ${glyph_pad}px;
    border-radius: ${border_radius}px;
EOF
  else
    cat <<EOF
    min-width: ${glyph_width}px;
    padding: 0 ${glyph_pad}px;
    border-radius: ${border_radius}px;
EOF
  fi

  cat <<EOF
}

${label_sels} {
    font-size: ${font_size}px;
    transition: color 280ms cubic-bezier(0.4, 0, 0.2, 1);
}

${inactive_sels} {
    opacity: 0.65;
}

${active_sels} {
    opacity: 1;
}

${inactive_hover_sels} {
    opacity: 1;
}

${hidden_sels} {
    min-width: 0;
    padding: 0;
    margin: 0;
}

#custom-ws-0.ws-hit:not(.hidden) {
    margin-left: ${glyph_offset}px;
}
EOF

  if [[ "$slot_count" -gt 1 ]]; then
    printf '\n'
    for ((i = 1; i < slot_count; i++)); do
      if [[ "$i" -gt 1 ]]; then
        printf ',\n'
      fi
      printf '#custom-ws-%s.ws-hit:not(.hidden)' "$i"
    done
    cat <<EOF
 {
    margin-left: ${slot_margin}px;
}
EOF
  fi

  cat <<EOF

${active_sels} {
    padding: 0 ${glyph_pad}px;
    background-color: transparent;
    background-image: linear-gradient(90deg, ${workspace_active} 0%, ${workspace_active} 100%);
EOF

  if [[ "$fit_content" -eq 1 ]]; then
    cat <<EOF
    background-size: 100% 100%;
    background-position: center;
    background-repeat: no-repeat;
}
EOF
  else
    cat <<EOF
    background-size: ${pill_width}px 100%;
    background-position: center;
    background-repeat: no-repeat;
}
EOF
  fi

} >"$out"
