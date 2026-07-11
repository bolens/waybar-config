#!/usr/bin/env sh
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/github-status.json"
lock_dir="$cache_dir/github-status.lock.d"
script_dir="${0%/*}"
. "$script_dir/waybar-cache-helpers.sh"
if [ -f "$script_dir/waybar-settings.sh" ]; then
  . "$script_dir/waybar-settings.sh"
fi
ttl="$(waybar_module_interval github 300)"
stale_lock_ttl=30
preview_limit=$(waybar_settings_get '.github.preview_limit' '5')
case "$preview_limit" in
  ''|*[!0-9]*) preview_limit=5 ;;
esac

mkdir -p "$cache_dir"

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰊤" "Connecting to GitHub..." "normal"
  exit 0
fi

# --refresh mode
# shellcheck disable=SC1091
. "$script_dir/unicode-animations-lib.sh"

perform_github_checks_and_output() {
  if ! command -v gh >/dev/null 2>&1; then
    json=$(emit_waybar_json "󰊤" "GitHub CLI not installed" "disabled")
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
    
    json=$(emit_waybar_json "󰊤" "$tooltip" "$class")
  else
    json=$(printf '%s' "$raw_notifs" | jq -c --argjson limit "$preview_limit" '
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
          [ .[] | "- [\(.repository.full_name)] \(.subject.title | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")) (\(.reason))" ] as $items |
          ($items[0:$limit] | join("\n")) as $preview |
          (if $len > $limit then "\n... and \($len - $limit) more" else "" end) as $more |
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
    json=$(emit_waybar_json "󰊤" "Error parsing GitHub notifications" "disabled")
  fi

  printf '%s\n' "$json"

  tmp_cache="$cache_file.tmp.$$"
  printf '%s\n' "$json" > "$tmp_cache"
  mv -f "$tmp_cache" "$cache_file"
}

animate_command dots "Checking GitHub..." "Connecting to api.github.com..." perform_github_checks_and_output
