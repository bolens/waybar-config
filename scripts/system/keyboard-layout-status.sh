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

qdbus_cmd() {
  if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 "$@"
  elif command -v qdbus >/dev/null 2>&1; then
    qdbus "$@"
  else
    return 1
  fi
}

case "$comp" in
  kde)
    # Plasma Wayland: org.kde.keyboard (setxkbmap is X11-only).
    current="$(qdbus_cmd org.kde.keyboard /Layouts org.kde.KeyboardLayouts.getCurrentLayout 2>/dev/null || true)"
    if [ -n "$current" ]; then
      layout="$current"
    fi
    if [ -z "$layout" ]; then
      layout="$(qdbus_cmd org.kde.keyboard /Layouts org.kde.KeyboardLayouts.getLayoutsList 2>/dev/null \
        | head -n1 | sed 's/,.*//' || true)"
    fi
    ;;
  hyprland)
    if command -v hyprctl >/dev/null 2>&1; then
      raw="$(hyprctl devices -j 2>/dev/null || true)"
      if [ -n "$raw" ]; then
        read -r hypr_layout hypr_variant <<EOF
$(printf '%s' "$raw" | jq -r '[.keyboards[0].active_keymap // "", .keyboards[0].active_variant // ""] | @tsv' 2>/dev/null)
EOF
        [ -n "$hypr_layout" ] && layout="$hypr_layout"
        [ -n "$hypr_variant" ] && variant="$hypr_variant"
      fi
    fi
    ;;
  *)
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
    ;;
esac

[ -n "$layout" ] || layout="??"
label="$(printf '%s' "$layout" | tr '[:lower:]' '[:upper:]')"
# Keep labels short for the bar (e.g. "English (US)" → parenthetical / first token).
case "$label" in
  *" "*)
    short="$(printf '%s' "$layout" | sed -n 's/.*(\([^)]*\)).*/\1/p')"
    if [ -n "$short" ]; then
      label="$(printf '%s' "$short" | tr '[:lower:]' '[:upper:]')"
    else
      label="$(printf '%s' "$layout" | awk '{print toupper($1)}')"
    fi
    ;;
esac
tooltip="Keyboard layout: ${layout}"
[ -n "$variant" ] && [ "$variant" != "None" ] && tooltip="${tooltip} (${variant})"

emit_waybar_json "$label" "$tooltip" "$layout"
