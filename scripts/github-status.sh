#!/usr/bin/env sh
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/github-status.json"
lock_dir="$cache_dir/github-status.lock.d"
ttl=300 # 5 minutes cache
stale_lock_ttl=30

mkdir -p "$cache_dir"

script_dir="${0%/*}"
# shellcheck disable=SC1091
. "$script_dir/waybar-cache-helpers.sh"


if [ "${1:-}" != "--refresh" ]; then
  if [ -f "$cache_file" ] && [ "$(cache_file_age "$cache_file")" -le "$ttl" ] 2>/dev/null; then
    cat "$cache_file"
    exit 0
  fi
  
  cleanup_stale_lock_dir "$lock_dir" "$stale_lock_ttl"
  [ -d "$lock_dir" ] || refresh_in_background
  
  if [ -f "$cache_file" ]; then
    cat "$cache_file"
    exit 0
  fi
  
  jq -cn --arg text "󰊤" --arg tooltip "Connecting to GitHub..." --arg class "normal" \
    '{text:$text, tooltip:$tooltip, class:$class}'
  exit 0
fi

# --refresh mode
# shellcheck disable=SC1091
. "$script_dir/unicode-animations-lib.sh"

perform_github_checks_and_output() {
  if ! command -v gh >/dev/null 2>&1; then
    json=$(jq -cn --arg text "󰊤" --arg tooltip "GitHub CLI not installed" --arg class "disabled" \
      '{text:$text, tooltip:$tooltip, class:$class}')
    printf '%s\n' "$json"
    
    tmp_cache="$cache_file.tmp.$$"
    printf '%s\n' "$json" > "$tmp_cache"
    mv -f "$tmp_cache" "$cache_file"
    return 0
  fi

  # Fetch raw JSON of notifications
  raw_notifs=$(timeout 10 gh api notifications 2>/dev/null || true)

  if [ -z "$raw_notifs" ] || [ "$raw_notifs" = "[]" ]; then
    # No notifications or offline
    if [ -z "$raw_notifs" ]; then
      tooltip="Unable to connect to GitHub\n\nLeft: open notifications · Right: github.com · Middle: refresh"
      class="disabled"
    else
      tooltip="No unread notifications\n\nLeft: open notifications · Right: github.com · Middle: refresh"
      class="normal"
    fi
    
    json=$(jq -cn --arg text "󰊤" --arg tooltip "$tooltip" --arg class "$class" \
      '{text:$text, tooltip:$tooltip, class:$class}')
  else
    json=$(printf '%s' "$raw_notifs" | jq -c '
      if type != "array" then
        {
          text: "󰊤",
          tooltip: "GitHub API error: \(if type == "object" and .message != null then .message else "invalid response format" end)\n\nLeft: open notifications · Right: github.com · Middle: refresh",
          class: "disabled"
        }
      else
        (length // 0) as $len |
        if $len == 0 then
          {
            text: "󰊤",
            tooltip: "No unread notifications\n\nLeft: open notifications · Right: github.com · Middle: refresh",
            class: "normal"
          }
        else
          [ .[] | "- [\(.repository.full_name)] \(.subject.title) (\(.reason))" ] as $items |
          ($items[0:5] | join("\n")) as $preview |
          (if $len > 5 then "\n... and \($len - 5) more" else "" end) as $more |
          {
            text: "󰊤 \($len)",
            tooltip: "GitHub Notifications: \($len) unread\n\nLatest:\n\($preview)\($more)\n\nLeft: open notifications · Right: github.com · Middle: refresh",
            class: "warning"
          }
        end
      end
    ' 2>/dev/null || echo "")
  fi

  if [ -z "$json" ]; then
    json=$(jq -cn --arg text "󰊤" --arg tooltip "Error parsing GitHub notifications" --arg class "disabled" \
      '{text:$text, tooltip:$tooltip, class:$class}')
  fi

  printf '%s\n' "$json"

  tmp_cache="$cache_file.tmp.$$"
  printf '%s\n' "$json" > "$tmp_cache"
  mv -f "$tmp_cache" "$cache_file"
}

animate_command dots "Checking GitHub..." "Connecting to api.github.com..." perform_github_checks_and_output
