#!/usr/bin/env sh
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"

layout=""
variant=""
tip_layout=""
comp="$(detect_compositor)"

qdbus_bin() {
  if command -v qdbus6 >/dev/null 2>&1; then
    command -v qdbus6
  elif command -v qdbus >/dev/null 2>&1; then
    command -v qdbus
  else
    return 1
  fi
}

qdbus_cmd() {
  _bin="$(qdbus_bin)" || return 1
  "$_bin" "$@"
}

# Plasma KeyboardLayouts API (current): getLayout() → index; getLayoutsList() → a(sss).
# Older string-returning layout getters were removed; using their error text as a label
# produced bar text like SIGNATURE with empty quotes.
plasma_layout() {
  _bin="$(qdbus_bin)" || return 1
  idx="$("$_bin" org.kde.keyboard /Layouts org.kde.KeyboardLayouts.getLayout 2>/dev/null || true)"
  case "$idx" in
    '' | *[!0-9]*) return 1 ;;
  esac
  command -v python3 >/dev/null 2>&1 || return 1

  parsed="$(
    "$_bin" --literal org.kde.keyboard /Layouts org.kde.KeyboardLayouts.getLayoutsList 2>/dev/null \
      | python3 -c '
import re, sys
idx = int(sys.argv[1])
raw = sys.stdin.read()
entries = re.findall(r"\(sss\)\s*\"([^\"]*)\",\s*\"([^\"]*)\",\s*\"([^\"]*)\"", raw)
if not entries or idx < 0 or idx >= len(entries):
    sys.exit(1)
short, var, display = entries[idx]
print(short or "")
print(var or "")
print(display or short or "??")
' "$idx" 2>/dev/null || true
  )"
  [ -n "$parsed" ] || return 1

  short="$(printf '%s\n' "$parsed" | sed -n '1p')"
  var="$(printf '%s\n' "$parsed" | sed -n '2p')"
  display="$(printf '%s\n' "$parsed" | sed -n '3p')"
  tip_layout="${display:-$short}"
  layout="${short:-$display}"
  variant="$var"
  [ -n "$layout" ] || return 1
  return 0
}

case "$comp" in
  kde)
    plasma_layout || true
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

# Never surface DBus/error blobs as layout labels.
case "$layout" in
  '' | Error:* | *"No such method"* | *"signature"*)
    layout="??"
    tip_layout=""
    ;;
esac

[ -n "$tip_layout" ] || tip_layout="$layout"

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

tooltip="Keyboard layout: ${tip_layout}"
[ -n "$variant" ] && [ "$variant" != "None" ] && tooltip="${tooltip} (${variant})"

class="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '_' | cut -c1-32)"
[ -n "$class" ] || class="unknown"

emit_waybar_json "$label" "$tooltip" "$class"
