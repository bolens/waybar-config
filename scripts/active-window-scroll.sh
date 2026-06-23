#!/usr/bin/env bash
# Continuous scrolling active window title module using zscroll.
set -euo pipefail

script_dir="$(CDPATH="" cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$script_dir/compositor-session.sh"

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

# Run zscroll in unbuffered mode to watch the cache file
# We check the file every 0.5s for changes, but scroll every 0.3s
zscroll -l 40 \
        --delay 0.3 \
        --update-check true \
        --update-interval 0.5 \
        --eval-in-shell true \
        "cat '$cache_file' 2>/dev/null" | while IFS= read -r scrolled; do
  
  # Read the original full title
  if [ -f "$cache_file" ]; then
    original=$(cat "$cache_file" 2>/dev/null || echo "")
  else
    original=""
  fi

  # Determine JSON fields
  if [ -z "$scrolled" ] || [ "$scrolled" = "Desktop" ] || [ "$scrolled" = "󰇄  Desktop" ]; then
    text="󰇄  Desktop"
    tooltip="No active window"
    class="desktop"
  else
    text="󰖲  $scrolled"
    tooltip="$original"
    class="active"
  fi

  # Escape special characters for JSON
  escaped_text="${text//\\/\\\\}"
  escaped_text="${escaped_text//\"/\\\"}"
  escaped_tooltip="${tooltip//\\/\\\\}"
  escaped_tooltip="${escaped_tooltip//\"/\\\"}"

  printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$escaped_text" "$escaped_tooltip" "$class"
done
