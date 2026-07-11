#!/usr/bin/env sh
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

layout=""
variant=""
comp="$(detect_compositor)"

if command -v setxkbmap >/dev/null 2>&1; then
  while read -r key val; do
    case "$key" in
      layout:) layout="$val" ;;
      variant:) variant="$val" ;;
    esac
  done <<EOF
$(setxkbmap -query 2>/dev/null)
EOF
fi

if [ "$comp" = "hyprland" ] && command -v hyprctl >/dev/null 2>&1; then
  raw="$(hyprctl devices -j 2>/dev/null || true)"
  if [ -n "$raw" ]; then
    read -r hypr_layout hypr_variant <<EOF
$(printf '%s' "$raw" | jq -r '[.keyboards[0].active_keymap // "", .keyboards[0].active_variant // ""] | @tsv' 2>/dev/null)
EOF
    [ -n "$hypr_layout" ] && layout="$hypr_layout"
    [ -n "$hypr_variant" ] && variant="$hypr_variant"
  fi
fi

[ -n "$layout" ] || layout="??"
label="$(printf '%s' "$layout" | tr '[:lower:]' '[:upper:]')"
tooltip="Keyboard layout: ${layout}"
[ -n "$variant" ] && [ "$variant" != "None" ] && tooltip="${tooltip} (${variant})"

emit_waybar_json "$label" "$tooltip" "$layout"
