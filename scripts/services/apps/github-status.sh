#!/usr/bin/env bash
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/github-status.json"
lock_dir="$cache_dir/github-status.lock.d"
# shellcheck source=../../lib/waybar-cache-helpers.sh
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
if [ -f "$WAYBAR_SCRIPTS/lib/waybar-settings.sh" ]; then
  # shellcheck source=../../lib/waybar-settings.sh
  . "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"
fi
ttl="$(waybar_module_interval github 300)"
stale_lock_ttl=30
preview_limit=$(waybar_settings_get '.github.preview_limit' '5')
show_reviews=$(waybar_settings_get '.github.show_reviews' 'true')
case "$preview_limit" in
  '' | *[!0-9]*) preview_limit=5 ;;
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
# shellcheck source=../../lib/unicode-animations-lib.sh
. "$WAYBAR_SCRIPTS/lib/unicode-animations-lib.sh"

perform_github_checks_and_output() {
  if ! command -v gh >/dev/null 2>&1; then
    json=$(emit_waybar_json "󰊤" "GitHub CLI not installed" "disabled")
    printf '%s\n' "$json"

    tmp_cache="$cache_file.tmp.$$"
    printf '%s\n' "$json" >"$tmp_cache"
    mv -f "$tmp_cache" "$cache_file"
    return 0
  fi

  raw_notifs=$(timeout 10 gh api notifications 2>/dev/null || true)

  review_count=0
  review_preview=""
  if [ "$show_reviews" = "true" ]; then
    review_json=$(timeout 10 gh api "search/issues?q=is:open+is:pr+review-requested:@me&per_page=5" 2>/dev/null || true)
    if [ -n "$review_json" ]; then
      review_count=$(printf '%s' "$review_json" | jq -r '.total_count // 0' 2>/dev/null || echo 0)
      case "$review_count" in '' | *[!0-9]*) review_count=0 ;; esac
      review_preview=$(printf '%s' "$review_json" | jq -r '
        (.items // [])[:5]
        | map("- [\(.repository_url | split("/")[-2:] | join("/"))] \(.title)")
        | join("\n")
      ' 2>/dev/null || true)
    fi
  fi

  notif_count=0
  notif_preview=""
  notif_class="normal"
  offline=0

  if [ -z "$raw_notifs" ]; then
    offline=1
  elif [ "$raw_notifs" = "[]" ]; then
    notif_count=0
  else
    parsed=$(printf '%s' "$raw_notifs" | jq -c --argjson limit "$preview_limit" '
      if type != "array" then
        {ok:false, count:0, preview:"", err:(if type=="object" and .message!=null then .message else "invalid response" end)}
      else
        (length // 0) as $len |
        [ .[] | "- [\(.repository.full_name)] \(.subject.title | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")) (\(.reason))" ] as $items |
        {
          ok:true,
          count:$len,
          preview: ($items[0:$limit] | join("\n")),
          more: (if $len > $limit then "\n... and \($len - $limit) more" else "" end),
          err:""
        }
      end
    ' 2>/dev/null || echo "")
    if [ -z "$parsed" ]; then
      offline=1
    else
      ok=$(printf '%s' "$parsed" | jq -r '.ok')
      if [ "$ok" != "true" ]; then
        err=$(printf '%s' "$parsed" | jq -r '.err')
        json=$(emit_waybar_json "󰊤" "GitHub API error: ${err}\n\nLeft: open notifications · Right: github.com · Middle: refresh" "disabled")
        printf '%s\n' "$json"
        tmp_cache="$cache_file.tmp.$$"
        printf '%s\n' "$json" >"$tmp_cache"
        mv -f "$tmp_cache" "$cache_file"
        return 0
      fi
      notif_count=$(printf '%s' "$parsed" | jq -r '.count')
      notif_preview=$(printf '%s' "$parsed" | jq -r '.preview + (.more // "")')
      if [ "$notif_count" -gt 0 ]; then
        notif_class="warning"
      fi
    fi
  fi

  if [ "$offline" -eq 1 ] && [ "$review_count" -eq 0 ]; then
    json=$(emit_waybar_json "󰊤" "Unable to connect to GitHub\n\nLeft: open notifications · Right: github.com · Middle: refresh" "disabled")
  else
    text="󰊤"
    bits=""
    [ "$notif_count" -gt 0 ] && bits="${notif_count}"
    if [ "$review_count" -gt 0 ]; then
      if [ -n "$bits" ]; then
        bits="${bits}·${review_count}r"
      else
        bits="${review_count}r"
      fi
    fi
    [ -n "$bits" ] && text="󰊤 ${bits}"

    class="$notif_class"
    if [ "$review_count" -gt 0 ] && [ "$class" = "normal" ]; then
      class="warning"
    fi
    if [ "$offline" -eq 1 ]; then
      class="disabled"
    fi

    tooltip="GitHub"
    tooltip="${tooltip}\nNotifications: ${notif_count} unread"
    tooltip="${tooltip}\nReview requests: ${review_count}"
    if [ -n "$notif_preview" ]; then
      tooltip="${tooltip}\n\nLatest notifications:\n${notif_preview}"
    fi
    if [ -n "$review_preview" ]; then
      tooltip="${tooltip}\n\nPRs awaiting review:\n${review_preview}"
    fi
    tooltip="${tooltip}\n\nLeft: open notifications · Right: github.com · Middle: refresh"

    json=$(emit_waybar_json "$text" "$tooltip" "$class")
  fi

  printf '%s\n' "$json"
  tmp_cache="$cache_file.tmp.$$"
  printf '%s\n' "$json" >"$tmp_cache"
  mv -f "$tmp_cache" "$cache_file"
}

animate_command dots "Checking GitHub..." "Connecting to api.github.com..." perform_github_checks_and_output
