#!/usr/bin/env bash
# Compositor-aware active window title for the center bar (KDE + Hyprland).
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
# shellcheck source=compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
# shellcheck source=waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck source=output-lib.sh
. "$WAYBAR_SCRIPTS/lib/output-lib.sh"

max_len=70
session="$(detect_compositor)"

output_arg="${1:-${WAYBAR_OUTPUT_NAME:-}}"
if [ -n "$output_arg" ]; then
  export WAYBAR_OUTPUT_NAME="$output_arg"
fi

per_output=0
_aw_po=$(waybar_settings_get '.active_window.per_output' 'true')
_ed_po=$(waybar_settings_get '.hypr_tools.empty_desktop_per_output' 'true')
case "$_aw_po" in false | False | FALSE | 0 | no | No | NO | off | Off | OFF) ;; *)
  [ -n "${WAYBAR_OUTPUT_NAME:-}" ] && per_output=1
  ;;
esac
if [ "$per_output" -eq 0 ]; then
  case "$_ed_po" in false | False | FALSE | 0 | no | No | NO | off | Off | OFF) ;; *)
    [ -n "${WAYBAR_OUTPUT_NAME:-}" ] && per_output=1
    ;;
  esac
fi

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
if [ "$per_output" -eq 1 ] && [ -n "${WAYBAR_OUTPUT_NAME:-}" ]; then
  _safe=$(waybar_css_class_for_output "$WAYBAR_OUTPUT_NAME")
  cache_file="$cache_dir/active-window-${_safe}.json"
else
  cache_file="$cache_dir/active-window.json"
fi

escape_markup() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

desktop_json() {
  jq -cn '{text:"󰇄  Desktop",tooltip:"No active window",class:"desktop"}'
}

emit_json() {
  local title="$1"
  local tooltip="$2"
  local esc_title
  esc_title=$(escape_markup "$title")
  local esc_tooltip
  esc_tooltip=$(escape_markup "$tooltip")
  jq -cn --arg text "󰖲  $esc_title" --arg tooltip "$esc_tooltip" '{text:$text,tooltip:$tooltip,class:"active"}'
}

trim_title() {
  local s="$1"
  local max="${2:-$max_len}"
  s="${s//$'\n'/ }"
  s="${s//$'\t'/ }"
  s="$(printf '%s' "$s" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  s="$(printf '%s' "$s" | sed -E 's/(.*) - Mozilla Firefox/\1/; s/(.*) - Zen Browser/\1/; s/(.*) - Google Chrome/\1/; s/(.*) - Floorp/\1/; s/(.*) - Chromium/\1/; s/(.*) - Brave/\1/; s/(.*) - Vivaldi/\1/')"
  if [ "${#s}" -le "$max" ]; then
    printf '%s' "$s"
  else
    printf '%s...' "${s:0:$((max - 3))}"
  fi
}

hypr_title_for_output() {
  local out="${1:-}"
  if ! command -v hyprctl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  if [ -z "$out" ]; then
    hyprctl activewindow -j 2>/dev/null | jq -r '.title // empty' || true
    return 0
  fi
  local mid
  mid=$(hyprctl monitors -j 2>/dev/null | jq -r --arg n "$out" '.[] | select(.name == $n) | .id' | head -n1 || true)
  if [ -z "$mid" ]; then
    hyprctl activewindow -j 2>/dev/null | jq -r '.title // empty' || true
    return 0
  fi
  hyprctl clients -j 2>/dev/null | jq -r --argjson mid "$mid" '
    [.[] | select(.monitor == $mid and ((.mapped // true) == true))]
    | sort_by(.focusHistoryID // 9999)
    | .[0].title // empty
  ' || true
}

case "$session" in
  hyprland)
    command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || {
      desktop_json
      exit 0
    }
    if [ "$per_output" -eq 1 ]; then
      title="$(hypr_title_for_output "${WAYBAR_OUTPUT_NAME:-}")"
    else
      title="$(hyprctl activewindow -j 2>/dev/null | jq -r '.title // empty' || true)"
    fi
    if [ -n "$title" ]; then
      trimmed="$(trim_title "$title")"
      emit_json "$trimmed" "$title"
    else
      desktop_json
    fi
    ;;
  kde)
    if [ -s "$cache_file" ]; then
      cat "$cache_file"
    elif [ "$per_output" -eq 1 ] && [ -s "$cache_dir/active-window.json" ]; then
      # Best-effort: fall back to global KDE cache when per-screen missing.
      cat "$cache_dir/active-window.json"
    else
      desktop_json
    fi
    ;;
  *)
    desktop_json
    ;;
esac
