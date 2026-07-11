#!/usr/bin/env bash
# Continuous scrolling active window title module using zscroll.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="$(CDPATH="" cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$WAYBAR_SCRIPTS/lib/compositor-session.sh"
# shellcheck disable=SC1091
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/active-window-title.raw"
mkdir -p "$cache_dir"

session="$(detect_compositor)"

# Initialize title for Hyprland at startup
if [ "$session" = "hyprland" ]; then
  if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    title="$(hyprctl activewindow -j 2>/dev/null | jq -r '.title // empty' || true)"
    title="${title//$'\n'/ }"
    title="${title//$'\t'/ }"
    title="$(printf '%s' "$title" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
    title="$(printf '%s' "$title" | sed -E 's/(.*) - Mozilla Firefox/\1/; s/(.*) - Zen Browser/\1/; s/(.*) - Google Chrome/\1/; s/(.*) - Floorp/\1/; s/(.*) - Chromium/\1/; s/(.*) - Brave/\1/; s/(.*) - Vivaldi/\1/')"
    echo "$title" > "$cache_file"
  else
    echo "" > "$cache_file"
  fi
elif [ "$session" = "kde" ]; then
  # For KDE, if the raw file doesn't exist yet, try to initialize it from the json cache
  if [ ! -f "$cache_file" ]; then
    json_cache="$cache_dir/active-window.json"
    if [ -f "$json_cache" ] && command -v jq >/dev/null 2>&1; then
      title="$(jq -r '.tooltip // empty' "$json_cache" 2>/dev/null || true)"
      echo "$title" > "$cache_file"
    else
      echo "" > "$cache_file"
    fi
  fi
else
  echo "" > "$cache_file"
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
