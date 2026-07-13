#!/usr/bin/env bash
# Continuous scrolling active window title module using zscroll.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="$(CDPATH="" cd -- "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/compositor-session.sh
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
# shellcheck source=../lib/waybar-settings.sh
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
# shellcheck source=../lib/output-lib.sh
. "$WAYBAR_SCRIPTS/lib/output-lib.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
mkdir -p "$cache_dir"

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

if [ "$per_output" -eq 1 ] && [ -n "${WAYBAR_OUTPUT_NAME:-}" ]; then
  _safe=$(waybar_css_class_for_output "$WAYBAR_OUTPUT_NAME")
  cache_file="$cache_dir/active-window-title-${_safe}.raw"
  json_cache="$cache_dir/active-window-${_safe}.json"
else
  cache_file="$cache_dir/active-window-title.raw"
  json_cache="$cache_dir/active-window.json"
fi

session="$(detect_compositor)"

# Normalize a raw window title for the cache / zscroll feed.
normalize_title() {
  local title="$1"
  title="${title//$'\n'/ }"
  title="${title//$'\t'/ }"
  title="$(printf '%s' "$title" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  title="$(printf '%s' "$title" | sed -E 's/(.*) - Mozilla Firefox/\1/; s/(.*) - Zen Browser/\1/; s/(.*) - Google Chrome/\1/; s/(.*) - Floorp/\1/; s/(.*) - Chromium/\1/; s/(.*) - Brave/\1/; s/(.*) - Vivaldi/\1/')"
  printf '%s' "$title"
}

# Hyprland: title of the most-recently-focused client on the given output (or global active).
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
  # Prefer lowest focusHistoryID on this monitor; empty → desktop.
  hyprctl clients -j 2>/dev/null | jq -r --argjson mid "$mid" '
    [.[] | select(.monitor == $mid and ((.mapped // true) == true))]
    | sort_by(.focusHistoryID // 9999)
    | .[0].title // empty
  ' || true
}

# Initialize title cache at startup
if [ "$session" = "hyprland" ]; then
  title="$(hypr_title_for_output "${WAYBAR_OUTPUT_NAME:-}")"
  title="$(normalize_title "$title")"
  echo "$title" >"$cache_file"
elif [ "$session" = "kde" ]; then
  # KDE: seed empty/missing per-output raw from global so zscroll is not stuck blank.
  _need_seed=0
  if [ ! -f "$cache_file" ]; then
    _need_seed=1
  elif [ ! -s "$cache_file" ] && [ "$per_output" -eq 1 ]; then
    _need_seed=1
  fi
  if [ "$_need_seed" -eq 1 ]; then
    if [ "$per_output" -eq 1 ] && [ -s "$cache_dir/active-window-title.raw" ]; then
      cp -f "$cache_dir/active-window-title.raw" "$cache_file" 2>/dev/null || echo "" >"$cache_file"
    elif [ -f "$json_cache" ] && command -v jq >/dev/null 2>&1; then
      title="$(jq -r '.tooltip // empty' "$json_cache" 2>/dev/null || true)"
      echo "$title" >"$cache_file"
    elif [ "$per_output" -eq 1 ] && [ -f "$cache_dir/active-window.json" ] && command -v jq >/dev/null 2>&1; then
      title="$(jq -r '.tooltip // empty' "$cache_dir/active-window.json" 2>/dev/null || true)"
      echo "$title" >"$cache_file"
    else
      echo "" >"$cache_file"
    fi
  fi
else
  echo "" >"$cache_file"
fi

# Load settings configuration
enable_scroll=$(waybar_settings_get '.active_window.zscroll' 'true')
scroll_len=$(waybar_settings_get '.active_window.max_length' '40')
scroll_delay=$(waybar_settings_get '.active_window.scroll_delay' '0.3')

escape_markup() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

output_title() {
  scrolled="$1"
  original="$2"

  if [ -z "$scrolled" ] || [ "$scrolled" = "Desktop" ] || [ "$scrolled" = "󰇄  Desktop" ]; then
    text="󰇄  Desktop"
    tooltip="No active window"
    class="desktop"
  else
    text="󰖲  $scrolled"
    tooltip="$original"
    class="active"
  fi

  # Escape XML/Pango markup entities
  escaped_markup_text=$(escape_markup "$text")
  escaped_markup_tooltip=$(escape_markup "$tooltip")

  # Escape special characters for JSON
  escaped_text="${escaped_markup_text//\\/\\\\}"
  escaped_text="${escaped_text//\"/\\\"}"
  escaped_tooltip="${escaped_markup_tooltip//\\/\\\\}"
  escaped_tooltip="${escaped_tooltip//\"/\\\"}"

  printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$escaped_text" "$escaped_tooltip" "$class"
}

# If zscroll is enabled and available, run it
if [ "$enable_scroll" = "true" ] && command -v zscroll >/dev/null 2>&1; then
  last_emitted=""
  zscroll -l "$scroll_len" \
    --delay "$scroll_delay" \
    --update-check true \
    --update-interval 0.5 \
    --eval-in-shell true \
    "cat '$cache_file' 2>/dev/null" | while IFS= read -r scrolled; do
    if [ -f "$cache_file" ]; then
      original=$(cat "$cache_file" 2>/dev/null || echo "")
    else
      original=""
    fi
    # Skip duplicate frames — each Waybar JSON update can dismiss open tooltips
    # on the bottom bar (continuous scroll × dual outputs).
    key="${scrolled}"$'\t'"${original}"
    if [ "$key" = "$last_emitted" ]; then
      continue
    fi
    last_emitted="$key"
    output_title "$scrolled" "$original"
  done
else
  # No scrolling. Monitor the raw file and truncate if longer than max_length.
  last_title=""
  while true; do
    if [ -f "$cache_file" ]; then
      original=$(cat "$cache_file" 2>/dev/null || echo "")
    else
      original=""
    fi

    if [ "$original" != "$last_title" ]; then
      if [ ${#original} -gt "$scroll_len" ]; then
        trunc_len=$((scroll_len - 3))
        [ $trunc_len -lt 1 ] && trunc_len=1
        truncated="${original:0:$trunc_len}..."
      else
        truncated="$original"
      fi
      output_title "$truncated" "$original"
      last_title="$original"
    fi
    sleep 0.5
  done
fi
