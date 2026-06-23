#!/usr/bin/env bash
# Data-driven dock launcher icons and click handlers (data/dock-apps.json).
set -euo pipefail

app_id="${1:-}"
action="${2:-status}"

script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
manifest="${WAYBAR_HOME:-$HOME/.config/waybar}/data/dock-apps.json"

if [ -z "$app_id" ] || [ ! -f "$manifest" ]; then
  exit 1
fi

run_detached() {
  if command -v setsid >/dev/null 2>&1; then
    setsid -f "$@" >/dev/null 2>&1 < /dev/null &
    return
  fi
  "$@" >/dev/null 2>&1 &
}

case "$action" in
  status)
    # Extract properties in a single jq process (tsv format: icon, tooltip, process_names)
    IFS=$'\t' read -r icon tooltip proc_list < <(jq -r --arg id "$app_id" '
      .[$id]
      | if . == null then empty
        else [
          (.icon // ""),
          (.tooltip // ""),
          ((.process_names // []) | join(","))
        ] | @tsv
        end
    ' "$manifest")

    is_running="false"
    if [ -n "$proc_list" ] && [ "$proc_list" != "null" ]; then
      # Split comma-separated process names
      IFS=',' read -ra proc_arr <<< "$proc_list"
      for name in "${proc_arr[@]}"; do
        if [ -n "$name" ] && pgrep -x "$name" >/dev/null 2>&1; then
          is_running="true"
          break
        fi
      done
    fi

    class="ready"
    if [ "$is_running" = "true" ]; then
      class="running"
    fi

    jq -cn \
      --arg text "${icon:-}" \
      --arg tooltip "${tooltip:-}" \
      --arg class "$class" \
      '{text:$text, tooltip:$tooltip, class:$class}'
    ;;
  click)
    field="${3:-on-click}"
    case "$field" in
      on-click) click_action="left" ;;
      on-click-middle) click_action="middle" ;;
      on-click-right) click_action="right" ;;
      left|middle|right) click_action="$field" ;;
      *)
        exit 1
        ;;
    esac
    run_detached "$script_dir/dock-app.sh" "$app_id" "$click_action"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
